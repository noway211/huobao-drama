import XCTest
@testable import ZdramaCore

final class LocalMp4ComposerTests: XCTestCase {
    func testEmptyInputs() {
        XCTAssertThrowsError(try LocalMp4Composer().validateInputs(paths: [], fileExists: { _ in true })) { error in
            XCTAssertEqual(error as? LocalMp4ComposerError, .emptyInputs)
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "请先生成并下载全部分镜视频后再合成成片"
            )
        }
    }

    func testMissingFileIsOneBased() {
        XCTAssertThrowsError(try LocalMp4Composer().validateInputs(paths: ["/a.mp4", "/b.mp4"], fileExists: { $0 == "/a.mp4" })) { error in
            XCTAssertEqual(error as? LocalMp4ComposerError, .missingFile(index: 2))
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "分镜 #2 的本地视频不存在，请重新生成视频"
            )
        }
    }

    func testIncompatibleResolution() {
        let a = MediaTrackSpec(videoMIME: "video/avc", width: 768, height: 1152, rotationDegrees: 0, audioMIME: nil, sampleRate: nil, channelCount: nil)
        let b = MediaTrackSpec(videoMIME: "video/avc", width: 768, height: 1280, rotationDegrees: 0, audioMIME: nil, sampleRate: nil, channelCount: nil)
        XCTAssertThrowsError(try LocalMp4Composer().validateCompatible(reference: a, candidate: b)) { error in
            XCTAssertEqual(error as? LocalMp4ComposerError, .incompatibleFormat)
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "分镜视频参数不一致，无法在本机无转码合成 MP4"
            )
        }
    }

    func testAudioPresenceMismatch() {
        let withAudio = MediaTrackSpec(
            videoMIME: "video/avc",
            width: 768,
            height: 1152,
            rotationDegrees: 0,
            audioMIME: "audio/mp4a-latm",
            sampleRate: 44100,
            channelCount: 2
        )
        let withoutAudio = MediaTrackSpec(
            videoMIME: "video/avc",
            width: 768,
            height: 1152,
            rotationDegrees: 0,
            audioMIME: nil,
            sampleRate: nil,
            channelCount: nil
        )
        XCTAssertThrowsError(try LocalMp4Composer().validateCompatible(reference: withAudio, candidate: withoutAudio)) { error in
            XCTAssertEqual(error as? LocalMp4ComposerError, .incompatibleFormat)
        }
    }

    func testCompatibleMatchingTracks() {
        let a = MediaTrackSpec(
            videoMIME: "video/avc",
            width: 768,
            height: 1152,
            rotationDegrees: 0,
            audioMIME: "audio/mp4a-latm",
            sampleRate: 44100,
            channelCount: 2
        )
        let b = MediaTrackSpec(
            videoMIME: "video/avc",
            width: 768,
            height: 1152,
            rotationDegrees: 0,
            audioMIME: "audio/mp4a-latm",
            sampleRate: 44100,
            channelCount: 2
        )
        XCTAssertNoThrow(try LocalMp4Composer().validateCompatible(reference: a, candidate: b))
    }

    func testShotImagePath() {
        let paths = GeneratedMediaPaths(root: URL(fileURLWithPath: "/tmp/app"))
        XCTAssertEqual(
            paths.shotImage(projectId: 3, shotId: 9, ext: "jpg").path,
            "/tmp/app/generated/3/shot_9_image.jpg"
        )
    }

    func testShotVideoAndFinalVideoPaths() {
        let paths = GeneratedMediaPaths(root: URL(fileURLWithPath: "/tmp/app"))
        XCTAssertEqual(
            paths.projectDir(3).path,
            "/tmp/app/generated/3"
        )
        XCTAssertEqual(
            paths.shotVideo(projectId: 3, shotId: 9, ext: "mp4").path,
            "/tmp/app/generated/3/shot_9_video.mp4"
        )
        XCTAssertEqual(
            paths.finalVideo(projectId: 3, episodeId: 2).path,
            "/tmp/app/generated/3/episode_2/final_video.mp4"
        )
    }

    func testExtensionFromURLKeepsAlphanumericCase() {
        XCTAssertEqual(MediaPathHelpers.extensionFromURL("https://x/a.PNG", kind: .image), "PNG")
        XCTAssertEqual(MediaPathHelpers.extensionFromURL("https://x/a.PNG", kind: .video), "PNG")
    }

    func testExtensionFromURLDefaultsWhenMissing() {
        XCTAssertEqual(MediaPathHelpers.extensionFromURL("https://x/file", kind: .image), "jpg")
        XCTAssertEqual(MediaPathHelpers.extensionFromURL("https://x/file", kind: .video), "mp4")
    }

    func testExtensionFromURLIgnoresQueryString() {
        XCTAssertEqual(MediaPathHelpers.extensionFromURL("https://x/a.jpg?token=1", kind: .image), "jpg")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(LocalMp4ComposerError.emptyInputs.errorDescription, "请先生成并下载全部分镜视频后再合成成片")
        XCTAssertEqual(LocalMp4ComposerError.missingFile(index: 1).errorDescription, "分镜 #1 的本地视频不存在，请重新生成视频")
        XCTAssertEqual(LocalMp4ComposerError.incompatibleFormat.errorDescription, "分镜视频参数不一致，无法在本机无转码合成 MP4")
        XCTAssertEqual(LocalMp4ComposerError.missingVideoTrack.errorDescription, "分镜视频缺少视频轨，无法合成 MP4")
        XCTAssertEqual(LocalMp4ComposerError.writeFailed.errorDescription, "成片 MP4 写入失败，请重试")
    }
}
