import Foundation

public enum GenerationStageKey {
    public static let text = "text"
    public static let rewrite = "rewrite"
    public static let storyboard = "storyboard"
    public static let image = "image"
    public static let video = "video"
    public static let finalVideo = "final_video"
    public static let full = "full"
}

public actor GenerationCoordinator {
    private struct Job {
        let id: UUID
        let projectId: Int64
        let episodeId: Int64
        let task: Task<Void, Never>
    }

    private let settingsStore: AgnesSettingsStore
    private let repository: DramaRepository
    private let scriptUseCase: GenerateProjectScriptUseCase
    private let rewriteUseCase: RewriteEpisodeScriptUseCase
    private let storyboardUseCase: GenerateStoryboardsUseCase
    private let imageUseCase: GenerateStoryboardImagesUseCase
    private let videoUseCase: GenerateStoryboardVideosUseCase
    private let composeUseCase: ComposeFinalVideoUseCase

    private var jobs: [String: Job] = [:]
    private var cancellingEpisodes: Set<EpisodeKey> = []

    private struct EpisodeKey: Hashable {
        let projectId: Int64
        let episodeId: Int64
    }

    public init(
        settingsStore: AgnesSettingsStore,
        repository: DramaRepository,
        scriptUseCase: GenerateProjectScriptUseCase,
        rewriteUseCase: RewriteEpisodeScriptUseCase,
        storyboardUseCase: GenerateStoryboardsUseCase,
        imageUseCase: GenerateStoryboardImagesUseCase,
        videoUseCase: GenerateStoryboardVideosUseCase,
        composeUseCase: ComposeFinalVideoUseCase
    ) {
        self.settingsStore = settingsStore
        self.repository = repository
        self.scriptUseCase = scriptUseCase
        self.rewriteUseCase = rewriteUseCase
        self.storyboardUseCase = storyboardUseCase
        self.imageUseCase = imageUseCase
        self.videoUseCase = videoUseCase
        self.composeUseCase = composeUseCase
    }

    public func isRunning(projectId: Int64, episodeId: Int64) -> Bool {
        jobs.values.contains { job in
            !job.task.isCancelled && job.projectId == projectId && job.episodeId == episodeId
        }
    }

    public func enqueue(
        projectId: Int64,
        episodeId: Int64,
        stage: String,
        forceRegenerate: Bool
    ) async {
        let episodeKey = EpisodeKey(projectId: projectId, episodeId: episodeId)
        guard !cancellingEpisodes.contains(episodeKey) else { return }

        let key = makeJobKey(projectId: projectId, episodeId: episodeId, stage: stage)
        if let existing = jobs[key] {
            guard forceRegenerate else { return }
            existing.task.cancel()
            await existing.task.value
            removeJob(key: key, id: existing.id)
        }

        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runJob(
                projectId: projectId,
                episodeId: episodeId,
                stage: stage,
                key: key,
                id: id
            )
        }
        jobs[key] = Job(
            id: id,
            projectId: projectId,
            episodeId: episodeId,
            task: task
        )
    }

    public func cancel(projectId: Int64, episodeId: Int64) async {
        let episodeKey = EpisodeKey(projectId: projectId, episodeId: episodeId)
        guard !cancellingEpisodes.contains(episodeKey) else { return }
        cancellingEpisodes.insert(episodeKey)

        let matching = jobs.compactMap { key, job -> (String, Job)? in
            guard keyBelongsToEpisode(key, episodeKey: episodeKey) else { return nil }
            return (key, job)
        }
        matching.forEach { $0.1.task.cancel() }
        for (_, job) in matching {
            await job.task.value
        }
        matching.forEach { key, job in
            removeJob(key: key, id: job.id)
        }

        defer { cancellingEpisodes.remove(episodeKey) }
        guard let project = try? repository.getProject(projectId) else { return }
        do {
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .cancelled,
                currentStage: project.currentStage,
                generatedScript: project.generatedScript,
                errorMessage: project.errorMessage
            )
        } catch {
            // Cancellation has no throwing public API; persistence errors do not revive a job.
        }
    }

    private func runJob(
        projectId: Int64,
        episodeId: Int64,
        stage: String,
        key: String,
        id: UUID
    ) async {
        defer { removeJob(key: key, id: id) }
        let settings = settingsStore.load()

        do {
            try await run(stage: stage, projectId: projectId, episodeId: episodeId, settings: settings)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func run(
        stage: String,
        projectId: Int64,
        episodeId: Int64,
        settings: AgnesSettings
    ) async throws {
        switch stage {
        case GenerationStageKey.text:
            _ = try await scriptUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
        case GenerationStageKey.rewrite:
            _ = try await rewriteUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
        case GenerationStageKey.storyboard:
            _ = try await storyboardUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
        case GenerationStageKey.image:
            try await imageUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
        case GenerationStageKey.video:
            try await videoUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
        case GenerationStageKey.finalVideo:
            _ = try await composeUseCase.execute(projectId: projectId, episodeId: episodeId)
        case GenerationStageKey.full:
            _ = try await scriptUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
            try Task.checkCancellation()
            _ = try await storyboardUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
            try Task.checkCancellation()
            try await imageUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
            try Task.checkCancellation()
            try await videoUseCase.execute(projectId: projectId, episodeId: episodeId, settings: settings)
            try Task.checkCancellation()
            _ = try await composeUseCase.execute(projectId: projectId, episodeId: episodeId)
        default:
            try repository.updateProjectTextResult(
                projectId: projectId,
                status: .failed,
                currentStage: .none,
                generatedScript: try repository.getProject(projectId)?.generatedScript,
                errorMessage: "Unknown generation stage: \(stage)"
            )
        }
    }

    private func makeJobKey(projectId: Int64, episodeId: Int64, stage: String) -> String {
        "generation-\(projectId)-\(episodeId)-\(stage)"
    }

    private func keyBelongsToEpisode(_ key: String, episodeKey: EpisodeKey) -> Bool {
        jobs[key].map {
            $0.projectId == episodeKey.projectId && $0.episodeId == episodeKey.episodeId
        } ?? false
    }

    private func removeJob(key: String, id: UUID) {
        guard jobs[key]?.id == id else { return }
        jobs.removeValue(forKey: key)
    }
}
