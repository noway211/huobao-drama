import Foundation

public protocol Mp4Composing: Sendable {
    func compose(inputPaths: [String], outputPath: String) async throws -> String
}

extension LocalMp4Composer: Mp4Composing {}

public struct ComposeFinalVideoUseCase {
    private let dramaRepository: DramaRepository
    private let composer: any Mp4Composing
    private let paths: GeneratedMediaPaths

    public init(dramaRepository: DramaRepository, composer: any Mp4Composing, paths: GeneratedMediaPaths) {
        self.dramaRepository = dramaRepository
        self.composer = composer
        self.paths = paths
    }

    public func execute(projectId: Int64, episodeId: Int64) async throws -> String {
        guard let project = try dramaRepository.getProject(projectId) else {
            throw LocalizedMessageError("项目不存在")
        }
        guard let episode = try dramaRepository.getEpisodeById(episodeId)
            ?? dramaRepository.getEpisodeForProject(projectId)
        else {
            throw LocalizedMessageError("剧集不存在")
        }

        let shots = try dramaRepository.getStoryboards(projectId: projectId, episodeId: episodeId)
            .sorted { $0.shotNumber < $1.shotNumber }
        if shots.isEmpty {
            let error = LocalizedMessageError("请先生成分镜")
            try markFailed(projectId: projectId, episodeId: episode.id, message: error.localizedDescription)
            throw error
        }

        let missingVideo = shots.first { shot in
            shot.videoStatus != .completed || !isExistingLocalFile(shot.videoLocalPath)
        }
        if missingVideo != nil {
            let error = LocalizedMessageError("请先生成并下载全部分镜视频后再合成成片")
            try markFailed(projectId: projectId, episodeId: episode.id, message: error.localizedDescription)
            throw error
        }

        try dramaRepository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .finalVideo,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )
        try dramaRepository.updateEpisodeFinalVideo(
            episodeId: episode.id,
            finalVideoStatus: .processing,
            finalVideoLocalPath: episode.finalVideoLocalPath,
            finalVideoErrorMessage: nil
        )

        let outputURL = paths.finalVideo(projectId: projectId, episodeId: episode.id)
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            let outputPath = try await composer.compose(
                inputPaths: shots.compactMap(\.videoLocalPath),
                outputPath: outputURL.path
            )
            try dramaRepository.updateProjectFinalVideo(
                projectId: projectId,
                status: .completed,
                currentStage: .finalVideo,
                finalVideoStatus: .completed,
                finalVideoLocalPath: outputPath,
                finalVideoErrorMessage: nil,
                errorMessage: nil
            )
            try dramaRepository.updateEpisodeFinalVideo(
                episodeId: episode.id,
                finalVideoStatus: .completed,
                finalVideoLocalPath: outputPath,
                finalVideoErrorMessage: nil
            )
            return outputPath
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try markFailed(projectId: projectId, episodeId: episode.id, message: error.localizedDescription)
            throw error
        }
    }

    private func markFailed(projectId: Int64, episodeId: Int64, message: String?) throws {
        try dramaRepository.updateProjectFinalVideo(
            projectId: projectId,
            status: .failed,
            currentStage: .finalVideo,
            finalVideoStatus: .failed,
            finalVideoLocalPath: nil,
            finalVideoErrorMessage: message,
            errorMessage: message
        )
        try dramaRepository.updateEpisodeFinalVideo(
            episodeId: episodeId,
            finalVideoStatus: .failed,
            finalVideoLocalPath: nil,
            finalVideoErrorMessage: message
        )
    }
}

private func isExistingLocalFile(_ path: String?) -> Bool {
    guard let path, !isBlank(path) else { return false }
    return FileManager.default.fileExists(atPath: path)
}
