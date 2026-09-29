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
            try repository.replaceStoryboards(projectId: projectId, episodeId: episodeId, shots: shots)
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .completed,
                currentStage: .storyboard,
                generatedScript: project.generatedScript,
                errorMessage: nil
            )
            return shots
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
}
