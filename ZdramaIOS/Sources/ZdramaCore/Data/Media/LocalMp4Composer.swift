import AVFoundation
import Foundation

public enum LocalMp4ComposerError: LocalizedError, Equatable {
    case emptyInputs
    case missingFile(index: Int)
    case missingVideoTrack
    case incompatibleFormat
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .emptyInputs:
            return "请先生成并下载全部分镜视频后再合成成片"
        case .missingFile(let index):
            return "分镜 #\(index) 的本地视频不存在，请重新生成视频"
        case .missingVideoTrack:
            return "分镜视频缺少视频轨，无法合成 MP4"
        case .incompatibleFormat:
            return "分镜视频参数不一致，无法在本机无转码合成 MP4"
        case .writeFailed:
            return "成片 MP4 写入失败，请重试"
        }
    }
}

public struct MediaTrackSpec: Equatable, Sendable {
    public var videoMIME: String
    public var width: Int
    public var height: Int
    public var rotationDegrees: Int
    public var audioMIME: String?
    public var sampleRate: Int?
    public var channelCount: Int?

    public init(
        videoMIME: String,
        width: Int,
        height: Int,
        rotationDegrees: Int,
        audioMIME: String?,
        sampleRate: Int?,
        channelCount: Int?
    ) {
        self.videoMIME = videoMIME
        self.width = width
        self.height = height
        self.rotationDegrees = rotationDegrees
        self.audioMIME = audioMIME
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public struct LocalMp4Composer: Sendable {
    public init() {}

    public func validateInputs(paths: [String], fileExists: (String) -> Bool) throws {
        if paths.isEmpty {
            throw LocalMp4ComposerError.emptyInputs
        }
        for (offset, path) in paths.enumerated() {
            if !fileExists(path) {
                throw LocalMp4ComposerError.missingFile(index: offset + 1)
            }
        }
    }

    public func validateCompatible(reference: MediaTrackSpec, candidate: MediaTrackSpec) throws {
        if reference.videoMIME != candidate.videoMIME
            || reference.width != candidate.width
            || reference.height != candidate.height
            || reference.rotationDegrees != candidate.rotationDegrees
        {
            throw LocalMp4ComposerError.incompatibleFormat
        }

        let referenceAudioNil = isAudioAbsent(reference)
        let candidateAudioNil = isAudioAbsent(candidate)
        if referenceAudioNil && candidateAudioNil {
            return
        }
        if reference.audioMIME == nil || candidate.audioMIME == nil {
            throw LocalMp4ComposerError.incompatibleFormat
        }
        if reference.audioMIME != candidate.audioMIME
            || reference.sampleRate != candidate.sampleRate
            || reference.channelCount != candidate.channelCount
        {
            throw LocalMp4ComposerError.incompatibleFormat
        }
    }

    public func compose(inputPaths: [String], outputPath: String) async throws -> String {
        try validateInputs(paths: inputPaths, fileExists: { FileManager.default.fileExists(atPath: $0) })

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw LocalMp4ComposerError.writeFailed
        }

        var compositionAudioTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        var referenceSpec: MediaTrackSpec?

        for path in inputPaths {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            let spec = try await trackSpec(from: asset)
            if let referenceSpec {
                try validateCompatible(reference: referenceSpec, candidate: spec)
            } else {
                referenceSpec = spec
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideo = videoTracks.first else {
                throw LocalMp4ComposerError.missingVideoTrack
            }

            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            do {
                try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            } catch {
                throw LocalMp4ComposerError.writeFailed
            }
            if cursor == .zero {
                compositionVideoTrack.preferredTransform = (try? await sourceVideo.load(.preferredTransform)) ?? .identity
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudio = audioTracks.first {
                if compositionAudioTrack == nil {
                    compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                }
                guard let compositionAudioTrack else {
                    throw LocalMp4ComposerError.writeFailed
                }
                do {
                    try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
                } catch {
                    throw LocalMp4ComposerError.writeFailed
                }
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try createParentDirectory(for: outputURL)
        try deleteExistingOutput(at: outputURL)
        try await exportPassthrough(composition: composition, outputURL: outputURL)
        return outputPath
    }

    private func isAudioAbsent(_ spec: MediaTrackSpec) -> Bool {
        spec.audioMIME == nil && spec.sampleRate == nil && spec.channelCount == nil
    }

    private func trackSpec(from asset: AVAsset) async throws -> MediaTrackSpec {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let video = videoTracks.first else {
            throw LocalMp4ComposerError.missingVideoTrack
        }

        let naturalSize = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let videoFormats = try await video.load(.formatDescriptions)
        let videoMIME = videoFormats.first.map { mime(from: $0, prefix: "video") } ?? "video/mp4"

        var audioMIME: String?
        var sampleRate: Int?
        var channelCount: Int?
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audio = audioTracks.first {
            let audioFormats = try await audio.load(.formatDescriptions)
            if let description = audioFormats.first {
                audioMIME = mime(from: description, prefix: "audio")
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                    sampleRate = Int(asbd.mSampleRate)
                    channelCount = Int(asbd.mChannelsPerFrame)
                }
            }
        }

        return MediaTrackSpec(
            videoMIME: videoMIME,
            width: Int(naturalSize.width.rounded()),
            height: Int(naturalSize.height.rounded()),
            rotationDegrees: rotationDegrees(from: transform),
            audioMIME: audioMIME,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    private func mime(from description: CMFormatDescription, prefix: String) -> String {
        "\(prefix)/\(fourCC(CMFormatDescriptionGetMediaSubType(description)))"
    }

    private func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    private func rotationDegrees(from transform: CGAffineTransform) -> Int {
        let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
        let normalized = degrees % 360
        return normalized < 0 ? normalized + 360 : normalized
    }

    /// 让非 Sendable 值（如 AVAssetExportSession）可被 @Sendable 取消回调安全捕获；
    /// 仅在单一 cancelExport() 调用场景下使用，值本身不被并发修改。
    private struct UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private func createParentDirectory(for outputURL: URL) throws {
        let parent = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw LocalMp4ComposerError.writeFailed
        }
    }

    private func deleteExistingOutput(at outputURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: outputURL.path) else { return }
        do {
            try fileManager.removeItem(at: outputURL)
        } catch {
            throw LocalMp4ComposerError.writeFailed
        }
    }

    private func exportPassthrough(composition: AVMutableComposition, outputURL: URL) async throws {
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw LocalMp4ComposerError.writeFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: LocalMp4ComposerError.writeFailed)
                    }
                }
            }
        } onCancel: {
            // AVAssetExportSession 非 Sendable，经 @unchecked 包装后仅在取消回调内只读使用。
            UncheckedSendableBox(value: session).value.cancelExport()
        }
    }
}
