import Foundation

public struct GenerateStoryboardVideosUseCase {
    private let repository: DramaRepository
    private let videoRepository: AgnesVideoRepository
    private let downloadRepository: MediaDownloadRepository

    public init(
        repository: DramaRepository,
        videoRepository: AgnesVideoRepository,
        downloadRepository: MediaDownloadRepository
    ) {
        self.repository = repository
        self.videoRepository = videoRepository
        self.downloadRepository = downloadRepository
    }

    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws {
        guard let project = try repository.getProject(projectId) else {
            throw LocalizedMessageError("Project not found")
        }
        let shots = try repository.getStoryboards(projectId: projectId, episodeId: episodeId)
        if shots.isEmpty {
            throw LocalizedMessageError("Generate storyboards before videos")
        }

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .video,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )

        for shot in shots {
            if shot.videoStatus == .completed && isExistingLocalFile(shot.videoLocalPath) {
                continue
            }

            try repository.updateShotVideo(
                shotId: shot.id,
                videoStatus: .processing,
                videoTaskId: shot.videoTaskId,
                videoUrl: shot.videoUrl,
                videoLocalPath: shot.videoLocalPath,
                videoErrorMessage: nil
            )

            var generatedTaskId = shot.videoTaskId
            var generatedUrl = shot.videoUrl
            do {
                let imageReference: String?
                if let path = shot.imageLocalPath, isExistingLocalFile(path) {
                    imageReference = try localImagePathToDataUri(path)
                } else {
                    imageReference = shot.imageUrl
                }
                let result = try await videoRepository.generateVideo(
                    settings: settings,
                    shot: shot,
                    imageReference: imageReference
                )
                generatedTaskId = result.taskId
                generatedUrl = result.videoUrl
                let localPath = try await downloadRepository.downloadShotVideo(
                    projectId: projectId,
                    shotId: shot.id,
                    url: result.videoUrl
                )
                try repository.updateShotVideo(
                    shotId: shot.id,
                    videoStatus: .completed,
                    videoTaskId: result.taskId,
                    videoUrl: result.videoUrl,
                    videoLocalPath: localPath,
                    videoErrorMessage: nil
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try repository.updateShotVideo(
                    shotId: shot.id,
                    videoStatus: .failed,
                    videoTaskId: generatedTaskId,
                    videoUrl: generatedUrl,
                    videoLocalPath: shot.videoLocalPath,
                    videoErrorMessage: error.localizedDescription
                )
                try repository.updateProjectTextResult(
                    projectId: projectId,
                    status: .failed,
                    currentStage: .video,
                    generatedScript: project.generatedScript,
                    errorMessage: error.localizedDescription
                )
                throw error
            }
        }

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .completed,
            currentStage: .video,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )
    }
}

private func isExistingLocalFile(_ path: String?) -> Bool {
    guard let path, !isBlank(path) else { return false }
    return FileManager.default.fileExists(atPath: path)
}

private func localImagePathToDataUri(_ path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    let mime: String
    switch ext {
    case "png":
        mime = "image/png"
    case "webp":
        mime = "image/webp"
    default:
        mime = "image/jpeg"
    }
    return "data:\(mime);base64,\(data.base64EncodedString())"
}
