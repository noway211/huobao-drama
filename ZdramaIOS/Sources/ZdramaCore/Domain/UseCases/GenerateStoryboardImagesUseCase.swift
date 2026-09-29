import Foundation

public struct GenerateStoryboardImagesUseCase {
    private let repository: DramaRepository
    private let imageRepository: AgnesImageRepository
    private let downloadRepository: MediaDownloadRepository

    public init(
        repository: DramaRepository,
        imageRepository: AgnesImageRepository,
        downloadRepository: MediaDownloadRepository
    ) {
        self.repository = repository
        self.imageRepository = imageRepository
        self.downloadRepository = downloadRepository
    }

    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws {
        guard let project = try repository.getProject(projectId) else {
            throw LocalizedMessageError("Project not found")
        }
        let shots = try repository.getStoryboards(projectId: projectId, episodeId: episodeId)
        if shots.isEmpty {
            throw LocalizedMessageError("Generate storyboards before images")
        }

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .image,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )

        for shot in shots {
            if shot.imageStatus == .completed && isExistingLocalFile(shot.imageLocalPath) {
                continue
            }

            try repository.updateShotImage(
                shotId: shot.id,
                imageStatus: .processing,
                imageUrl: shot.imageUrl,
                imageLocalPath: shot.imageLocalPath,
                imageErrorMessage: nil
            )

            var generatedUrl = shot.imageUrl
            do {
                let imageUrl = try await imageRepository.generateImage(
                    settings: settings,
                    prompt: shot.imagePrompt
                )
                generatedUrl = imageUrl
                let localPath = try await downloadRepository.downloadShotImage(
                    projectId: projectId,
                    shotId: shot.id,
                    url: imageUrl
                )
                try repository.updateShotImage(
                    shotId: shot.id,
                    imageStatus: .completed,
                    imageUrl: imageUrl,
                    imageLocalPath: localPath,
                    imageErrorMessage: nil
                )
            } catch {
                try repository.updateShotImage(
                    shotId: shot.id,
                    imageStatus: .failed,
                    imageUrl: generatedUrl,
                    imageLocalPath: shot.imageLocalPath,
                    imageErrorMessage: error.localizedDescription
                )
                try repository.updateProjectTextResult(
                    projectId: projectId,
                    status: .failed,
                    currentStage: .image,
                    generatedScript: project.generatedScript,
                    errorMessage: error.localizedDescription
                )
                throw error
            }
        }

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .completed,
            currentStage: .image,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )
    }
}

private func isExistingLocalFile(_ path: String?) -> Bool {
    guard let path, !isBlank(path) else { return false }
    return FileManager.default.fileExists(atPath: path)
}
