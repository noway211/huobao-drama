import Foundation

public struct GenerateStoryboardsUseCase {
    private let repository: DramaRepository
    private let storyboardRepository: AgnesStoryboardRepository

    public init(repository: DramaRepository, storyboardRepository: AgnesStoryboardRepository) {
        self.repository = repository
        self.storyboardRepository = storyboardRepository
    }

    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> [StoryboardShot] {
        guard let project = try repository.getProject(projectId) else {
            throw LocalizedMessageError("Project not found")
        }
        guard let episode = try repository.getEpisodeById(episodeId) else {
            throw LocalizedMessageError("Episode not found")
        }
        guard let script = episode.scriptContent, !isBlank(script) else {
            throw LocalizedMessageError("请先为本集创作或改写脚本")
        }

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .storyboard,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )

        do {
            let shots = try await storyboardRepository.generateStoryboards(
                settings: settings,
                project: project,
                script: script
            )
            // 替换前旧 shotId 的本地媒体文件将不再被引用，替换成功后清理。
            let oldShots = try repository.getStoryboards(projectId: projectId, episodeId: episodeId)
            try repository.replaceStoryboards(projectId: projectId, episodeId: episodeId, shots: shots)
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .completed,
                currentStage: .storyboard,
                generatedScript: project.generatedScript,
                errorMessage: nil
            )
            removeOrphanedMedia(oldShots)
            return shots
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .failed,
                currentStage: .storyboard,
                generatedScript: project.generatedScript,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    /// 删除被替换镜头遗留的本地媒体文件（仅当文件仍存在时；清理失败不应影响生成结果）。
    private func removeOrphanedMedia(_ oldShots: [StoryboardShot]) {
        let fileManager = FileManager.default
        for shot in oldShots {
            for path in [shot.imageLocalPath, shot.videoLocalPath] {
                guard let path, !path.isEmpty, fileManager.fileExists(atPath: path) else { continue }
                try? fileManager.removeItem(atPath: path)
            }
        }
    }
}
