import Foundation
import GRDB

public final class DramaRepository {
    private let filesRoot: URL
    private let projects: ProjectLocalDataSource
    private let episodes: EpisodeLocalDataSource
    private let storyboards: StoryboardLocalDataSource
    private let characters: CharacterLocalDataSource

    public init(db: DatabaseQueue, filesRoot: URL) {
        self.filesRoot = filesRoot
        self.projects = ProjectLocalDataSource(db: db)
        self.episodes = EpisodeLocalDataSource(db: db)
        self.storyboards = StoryboardLocalDataSource(db: db)
        self.characters = CharacterLocalDataSource(db: db)
    }

    public func createProject(_ project: DramaProject) throws -> Int64 {
        try projects.insertProject(project)
    }

    public func getProjects() throws -> [DramaProject] {
        try projects.getProjects()
    }

    public func getProject(_ id: Int64) throws -> DramaProject? {
        try projects.getProject(id)
    }

    public func updateProjectTextResult(
        projectId: Int64,
        status: ProjectStatus,
        currentStage: GenerationStage,
        generatedScript: String?,
        errorMessage: String?
    ) throws {
        try projects.updateProjectTextResult(
            projectId: projectId,
            status: status,
            currentStage: currentStage,
            generatedScript: generatedScript,
            errorMessage: errorMessage
        )
    }

    public func updateProjectFinalVideo(
        projectId: Int64,
        status: ProjectStatus,
        currentStage: GenerationStage,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?,
        errorMessage: String?
    ) throws {
        try projects.updateProjectFinalVideo(
            projectId: projectId,
            status: status,
            currentStage: currentStage,
            finalVideoStatus: finalVideoStatus,
            finalVideoLocalPath: finalVideoLocalPath,
            finalVideoErrorMessage: finalVideoErrorMessage,
            errorMessage: errorMessage
        )
    }

    public func failProcessingProjects(message: String) throws -> Int {
        try projects.failProcessingProjects(message: message)
    }

    public func createEpisodeForProject(projectId: Int64, title: String, content: String?) throws -> Int64 {
        let nextNumber = (try episodes.getEpisodes(projectId).map(\.episodeNumber).max() ?? 0) + 1
        let now = LocalClock.nowMillis()
        return try episodes.insertEpisode(
            Episode(
                id: 0,
                projectId: projectId,
                episodeNumber: nextNumber,
                title: title,
                content: content,
                scriptContent: nil,
                status: .draft,
                finalVideoStatus: .pending,
                finalVideoLocalPath: nil,
                finalVideoErrorMessage: nil,
                createdAt: now,
                updatedAt: now
            )
        )
    }

    public func getEpisodeById(_ id: Int64) throws -> Episode? {
        try episodes.getEpisodeById(id)
    }

    public func getEpisodeForProject(_ projectId: Int64) throws -> Episode? {
        try episodes.getEpisodeForProject(projectId)
    }

    public func getEpisodes(_ projectId: Int64) throws -> [Episode] {
        try episodes.getEpisodes(projectId)
    }

    public func updateEpisodeScriptContent(
        episodeId: Int64,
        scriptContent: String?,
        status: EpisodeStatus
    ) throws {
        try episodes.updateEpisodeScriptContent(
            episodeId: episodeId,
            scriptContent: scriptContent,
            status: status
        )
    }

    public func updateEpisodeFinalVideo(
        episodeId: Int64,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?
    ) throws {
        try episodes.updateEpisodeFinalVideo(
            episodeId: episodeId,
            finalVideoStatus: finalVideoStatus,
            finalVideoLocalPath: finalVideoLocalPath,
            finalVideoErrorMessage: finalVideoErrorMessage
        )
    }

    public func replaceStoryboards(projectId: Int64, episodeId: Int64, shots: [StoryboardShot]) throws {
        try storyboards.replaceStoryboards(projectId: projectId, episodeId: episodeId, shots: shots)
    }

    public func getStoryboards(projectId: Int64, episodeId: Int64) throws -> [StoryboardShot] {
        try storyboards.getStoryboards(projectId: projectId, episodeId: episodeId)
    }

    public func updateShotImage(
        shotId: Int64,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ) throws {
        try storyboards.updateShotImage(
            shotId: shotId,
            imageStatus: imageStatus,
            imageUrl: imageUrl,
            imageLocalPath: imageLocalPath,
            imageErrorMessage: imageErrorMessage
        )
    }

    public func updateShotVideo(
        shotId: Int64,
        videoStatus: AssetStatus,
        videoTaskId: String?,
        videoUrl: String?,
        videoLocalPath: String?,
        videoErrorMessage: String?
    ) throws {
        try storyboards.updateShotVideo(
            shotId: shotId,
            videoStatus: videoStatus,
            videoTaskId: videoTaskId,
            videoUrl: videoUrl,
            videoLocalPath: videoLocalPath,
            videoErrorMessage: videoErrorMessage
        )
    }

    public func updateShotImagePrompt(shotId: Int64, newPrompt: String) throws {
        try storyboards.updateShotImagePrompt(shotId: shotId, newPrompt: newPrompt)
    }

    public func updateShotVideoPrompt(shotId: Int64, newPrompt: String) throws {
        try storyboards.updateShotVideoPrompt(shotId: shotId, newPrompt: newPrompt)
    }

    public func deleteProject(_ projectId: Int64) throws -> Bool {
        try storyboards.deleteStoryboards(projectId: projectId)
        try characters.deleteCharactersForProject(projectId)
        try episodes.deleteEpisodesForProject(projectId)
        let deleted = try projects.deleteProject(projectId)
        let projectDir = GeneratedMediaPaths(root: filesRoot).projectDir(projectId)
        if FileManager.default.fileExists(atPath: projectDir.path) {
            try FileManager.default.removeItem(at: projectDir)
        }
        return deleted
    }
}
