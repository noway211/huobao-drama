import Foundation

public struct CreateDramaUseCase {
    private let repository: DramaRepository

    public init(repository: DramaRepository) {
        self.repository = repository
    }

    public func execute(_ input: CreateDramaInput) throws -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let project = DramaProject(
            id: 0,
            title: input.title,
            prompt: input.prompt,
            style: input.style,
            targetAudience: input.targetAudience,
            aspectRatio: input.aspectRatio,
            shotCount: input.shotCount,
            shotDurationSeconds: input.shotDurationSeconds,
            status: .draft,
            currentStage: .none,
            errorMessage: nil,
            generatedScript: nil,
            finalVideoStatus: .pending,
            finalVideoLocalPath: nil,
            finalVideoErrorMessage: nil,
            createdAt: now,
            updatedAt: now
        )
        let projectId = try repository.createProject(project)
        // Auto-create episode 1 with the prompt as raw content
        _ = try repository.createEpisodeForProject(
            projectId: projectId,
            title: input.title,
            content: input.prompt
        )
        return projectId
    }
}
