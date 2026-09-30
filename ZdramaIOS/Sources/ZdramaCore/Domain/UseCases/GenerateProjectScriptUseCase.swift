import Foundation

public struct GenerateProjectScriptUseCase {
    private let repository: DramaRepository
    private let textRepository: AgnesTextRepository

    public init(repository: DramaRepository, textRepository: AgnesTextRepository) {
        self.repository = repository
        self.textRepository = textRepository
    }

    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> String {
        guard let project = try repository.getProject(projectId) else {
            throw LocalizedMessageError("Project not found")
        }
        guard let episode = try repository.getEpisodeById(episodeId)
            ?? repository.getEpisodeForProject(projectId)
        else {
            throw LocalizedMessageError("Episode not found")
        }

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .text,
            generatedScript: project.generatedScript,
            errorMessage: nil
        )

        let storyPrompt: String
        if let content = episode.content, !isBlank(content) {
            storyPrompt = content
        } else {
            storyPrompt = project.prompt
        }

        do {
            let script = try await textRepository.generateScript(
                settings: settings,
                project: project,
                storyPrompt: storyPrompt
            )
            try repository.updateEpisodeScriptContent(
                episodeId: episode.id,
                scriptContent: script,
                status: .completed
            )
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .completed,
                currentStage: .text,
                generatedScript: script,
                errorMessage: nil
            )
            return script
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
                generatedScript: episode.scriptContent ?? project.generatedScript,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
}

struct LocalizedMessageError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

func isBlank(_ value: String?) -> Bool {
    value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
}
