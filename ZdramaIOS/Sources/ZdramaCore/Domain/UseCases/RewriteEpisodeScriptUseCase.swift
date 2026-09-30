import Foundation

public struct RewriteEpisodeScriptUseCase {
    private let repository: DramaRepository
    private let textRepository: AgnesTextRepository

    public init(repository: DramaRepository, textRepository: AgnesTextRepository) {
        self.repository = repository
        self.textRepository = textRepository
    }

    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> String {
        guard let episode = try repository.getEpisodeById(episodeId)
            ?? repository.getEpisodeForProject(projectId)
        else {
            throw LocalizedMessageError("Episode not found for project")
        }
        guard let rawContent = episode.content else {
            throw LocalizedMessageError("Episode has no raw content to rewrite")
        }
        if isBlank(rawContent) {
            throw LocalizedMessageError("Episode raw content is empty")
        }

        try repository.updateEpisodeScriptContent(
            episodeId: episode.id,
            scriptContent: episode.scriptContent,
            status: .rewriting
        )
        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .text,
            generatedScript: episode.scriptContent,
            errorMessage: nil
        )

        do {
            let scriptContent = try await textRepository.rewriteScript(
                settings: settings,
                rawContent: rawContent
            )
            try repository.updateEpisodeScriptContent(
                episodeId: episode.id,
                scriptContent: scriptContent,
                status: .completed
            )
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .completed,
                currentStage: .text,
                generatedScript: scriptContent,
                errorMessage: nil
            )
            return scriptContent
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try repository.updateEpisodeScriptContent(
                episodeId: episode.id,
                scriptContent: episode.scriptContent,
                status: .failed
            )
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .failed,
                currentStage: .text,
                generatedScript: episode.scriptContent,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
}
