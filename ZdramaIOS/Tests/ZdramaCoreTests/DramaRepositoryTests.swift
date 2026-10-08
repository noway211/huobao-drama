import XCTest
@testable import ZdramaCore

final class DramaRepositoryTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DramaRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        repository = DramaRepository(db: db, filesRoot: filesRoot)
    }

    override func tearDownWithError() throws {
        repository = nil
        if let filesRoot {
            try? FileManager.default.removeItem(at: filesRoot)
        }
        filesRoot = nil
    }

    func testCreateProjectThenGetProjectsReturnsIt() throws {
        let projectId = try repository.createProject(makeProject(title: "Alpha", prompt: "Write a short"))
        XCTAssertGreaterThan(projectId, 0)

        let listed = try repository.getProjects()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].id, projectId)
        XCTAssertEqual(listed[0].title, "Alpha")
        XCTAssertEqual(listed[0].prompt, "Write a short")
        XCTAssertEqual(listed[0].status, .draft)
        XCTAssertEqual(listed[0].currentStage, .none)
        XCTAssertEqual(listed[0].finalVideoStatus, .pending)
        XCTAssertGreaterThan(listed[0].createdAt, 0)
        XCTAssertGreaterThan(listed[0].updatedAt, 0)

        let fetched = try repository.getProject(projectId)
        XCTAssertEqual(fetched?.title, "Alpha")
        XCTAssertNil(try repository.getProject(projectId + 1))
    }

    func testGetProjectsOrdersByUpdatedAtDescending() throws {
        let olderId = try repository.createProject(makeProject(title: "Older", createdAt: 1_000, updatedAt: 1_000))
        let newerId = try repository.createProject(makeProject(title: "Newer", createdAt: 2_000, updatedAt: 2_000))
        XCTAssertEqual(try repository.getProjects().map(\.id), [newerId, olderId])
    }

    func testCreateEpisodeForProjectInsertsIncrementingNumbers() throws {
        let projectId = try repository.createProject(makeProject(title: "Show"))

        let episode1Id = try repository.createEpisodeForProject(
            projectId: projectId,
            title: "Episode 1",
            content: "first content"
        )
        let episode1 = try repository.getEpisodeById(episode1Id)
        XCTAssertEqual(episode1?.episodeNumber, 1)
        XCTAssertEqual(episode1?.title, "Episode 1")
        XCTAssertEqual(episode1?.content, "first content")
        XCTAssertNil(episode1?.scriptContent)
        XCTAssertEqual(episode1?.status, .draft)
        XCTAssertEqual(episode1?.finalVideoStatus, .pending)
        XCTAssertGreaterThan(episode1?.createdAt ?? 0, 0)

        let episode2Id = try repository.createEpisodeForProject(
            projectId: projectId,
            title: "Episode 2",
            content: nil
        )
        let episode2 = try repository.getEpisodeById(episode2Id)
        XCTAssertEqual(episode2?.episodeNumber, 2)
        XCTAssertNil(episode2?.content)

        let first = try repository.getEpisodeForProject(projectId)
        XCTAssertEqual(first?.id, episode1Id)
        XCTAssertEqual(first?.episodeNumber, 1)

        XCTAssertEqual(try repository.getEpisodes(projectId).map(\.episodeNumber), [1, 2])
        XCTAssertNil(try repository.getEpisodeById(episode2Id + 99))
    }

    func testReplaceStoryboardsDeletesPreviousRowsForThatEpisodeOnly() throws {
        let projectId = try repository.createProject(makeProject())
        let episode1Id = try repository.createEpisodeForProject(projectId: projectId, title: "E1", content: nil)
        let episode2Id = try repository.createEpisodeForProject(projectId: projectId, title: "E2", content: nil)

        try repository.replaceStoryboards(
            projectId: projectId,
            episodeId: episode1Id,
            shots: [
                makeShot(projectId: projectId, episodeId: episode1Id, shotNumber: 1, scene: "old-e1", characterNames: ["A"])
            ]
        )
        try repository.replaceStoryboards(
            projectId: projectId,
            episodeId: episode2Id,
            shots: [
                makeShot(projectId: projectId, episodeId: episode2Id, shotNumber: 1, scene: "keep-e2")
            ]
        )

        let originalEpisode1 = try repository.getStoryboards(projectId: projectId, episodeId: episode1Id)
        XCTAssertEqual(originalEpisode1.count, 1)
        let originalEpisode1Id = originalEpisode1[0].id
        XCTAssertEqual(originalEpisode1[0].characterNames, ["A"])

        try repository.replaceStoryboards(
            projectId: projectId,
            episodeId: episode1Id,
            shots: [
                makeShot(projectId: projectId, episodeId: episode1Id, shotNumber: 1, scene: "new-a", characterNames: ["B"]),
                makeShot(projectId: projectId, episodeId: episode1Id, shotNumber: 2, scene: "new-b")
            ]
        )

        let replaced = try repository.getStoryboards(projectId: projectId, episodeId: episode1Id)
        XCTAssertEqual(replaced.map(\.scene), ["new-a", "new-b"])
        XCTAssertEqual(replaced.map(\.shotNumber), [1, 2])
        XCTAssertFalse(replaced.map(\.id).contains(originalEpisode1Id))
        XCTAssertEqual(replaced[0].characterNames, ["B"])
        XCTAssertEqual(replaced[1].characterNames, [])

        let episode2Shots = try repository.getStoryboards(projectId: projectId, episodeId: episode2Id)
        XCTAssertEqual(episode2Shots.map(\.scene), ["keep-e2"])
    }

    func testFailProcessingProjectsFlipsProcessingToFailed() throws {
        let processingId = try repository.createProject(makeProject(title: "Busy", status: .processing, updatedAt: 10))
        let draftId = try repository.createProject(makeProject(title: "Idle", status: .draft, updatedAt: 20))

        let updated = try repository.failProcessingProjects(message: "生成任务中断（应用被关闭），请重新开始")
        XCTAssertEqual(updated, 1)

        let processing = try repository.getProject(processingId)
        XCTAssertEqual(processing?.status, .failed)
        XCTAssertEqual(processing?.errorMessage, "生成任务中断（应用被关闭），请重新开始")

        let draft = try repository.getProject(draftId)
        XCTAssertEqual(draft?.status, .draft)
        XCTAssertNil(draft?.errorMessage)

        XCTAssertEqual(try repository.failProcessingProjects(message: "again"), 0)
    }

    func testDeleteProjectRemovesRowsAndGeneratedDirectory() throws {
        let projectId = try repository.createProject(makeProject(title: "ToDelete"))
        let otherId = try repository.createProject(makeProject(title: "Keep"))
        let episodeId = try repository.createEpisodeForProject(projectId: projectId, title: "E1", content: "c")
        let otherEpisodeId = try repository.createEpisodeForProject(projectId: otherId, title: "KeepE", content: nil)
        try repository.replaceStoryboards(
            projectId: projectId,
            episodeId: episodeId,
            shots: [makeShot(projectId: projectId, episodeId: episodeId, shotNumber: 1, scene: "gone")]
        )
        try repository.replaceStoryboards(
            projectId: otherId,
            episodeId: otherEpisodeId,
            shots: [makeShot(projectId: otherId, episodeId: otherEpisodeId, shotNumber: 1, scene: "stay")]
        )

        let projectDir = GeneratedMediaPaths(root: filesRoot).projectDir(projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try Data("clip".utf8).write(to: projectDir.appendingPathComponent("shot.mp4"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectDir.path))

        XCTAssertTrue(try repository.deleteProject(projectId))
        XCTAssertNil(try repository.getProject(projectId))
        XCTAssertTrue(try repository.getEpisodes(projectId).isEmpty)
        XCTAssertTrue(try repository.getStoryboards(projectId: projectId, episodeId: episodeId).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDir.path))

        XCTAssertEqual(try repository.getProject(otherId)?.title, "Keep")
        XCTAssertEqual(try repository.getEpisodes(otherId).count, 1)
        XCTAssertEqual(try repository.getStoryboards(projectId: otherId, episodeId: otherEpisodeId).map(\.scene), ["stay"])

        XCTAssertFalse(try repository.deleteProject(projectId))
    }

    func testUpdateProjectEpisodeAndShotFields() throws {
        let projectId = try repository.createProject(makeProject())
        let episodeId = try repository.createEpisodeForProject(projectId: projectId, title: "E1", content: "draft")
        try repository.replaceStoryboards(
            projectId: projectId,
            episodeId: episodeId,
            shots: [makeShot(projectId: projectId, episodeId: episodeId, shotNumber: 1, scene: "s1")]
        )
        let shotId = try repository.getStoryboards(projectId: projectId, episodeId: episodeId)[0].id

        try repository.updateProjectTextResult(
            projectId: projectId,
            status: .processing,
            currentStage: .text,
            generatedScript: "script",
            errorMessage: nil
        )
        var project = try repository.getProject(projectId)
        XCTAssertEqual(project?.status, .processing)
        XCTAssertEqual(project?.currentStage, .text)
        XCTAssertEqual(project?.generatedScript, "script")

        try repository.updateProjectFinalVideo(
            projectId: projectId,
            status: .completed,
            currentStage: .finalVideo,
            finalVideoStatus: .completed,
            finalVideoLocalPath: "/tmp/final.mp4",
            finalVideoErrorMessage: nil,
            errorMessage: nil
        )
        project = try repository.getProject(projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, .finalVideo)
        XCTAssertEqual(project?.finalVideoStatus, .completed)
        XCTAssertEqual(project?.finalVideoLocalPath, "/tmp/final.mp4")

        try repository.updateEpisodeScriptContent(
            episodeId: episodeId,
            scriptContent: "rewritten",
            status: .completed
        )
        try repository.updateEpisodeFinalVideo(
            episodeId: episodeId,
            finalVideoStatus: .failed,
            finalVideoLocalPath: nil,
            finalVideoErrorMessage: "merge failed"
        )
        let episode = try repository.getEpisodeById(episodeId)
        XCTAssertEqual(episode?.scriptContent, "rewritten")
        XCTAssertEqual(episode?.status, .completed)
        XCTAssertEqual(episode?.finalVideoStatus, .failed)
        XCTAssertEqual(episode?.finalVideoErrorMessage, "merge failed")

        try repository.updateShotImage(
            shotId: shotId,
            imageStatus: .completed,
            imageUrl: "https://img",
            imageLocalPath: "/img.jpg",
            imageErrorMessage: nil
        )
        try repository.updateShotVideo(
            shotId: shotId,
            videoStatus: .processing,
            videoTaskId: "task-1",
            videoUrl: nil,
            videoLocalPath: nil,
            videoErrorMessage: nil
        )
        try repository.updateShotImagePrompt(shotId: shotId, newPrompt: "new image")
        try repository.updateShotVideoPrompt(shotId: shotId, newPrompt: "new video")
        let shot = try repository.getStoryboards(projectId: projectId, episodeId: episodeId)[0]
        XCTAssertEqual(shot.imageStatus, .completed)
        XCTAssertEqual(shot.imageUrl, "https://img")
        XCTAssertEqual(shot.imageLocalPath, "/img.jpg")
        XCTAssertEqual(shot.videoStatus, .processing)
        XCTAssertEqual(shot.videoTaskId, "task-1")
        XCTAssertEqual(shot.imagePrompt, "new image")
        XCTAssertEqual(shot.videoPrompt, "new video")
    }

    /// 回归：分镜被替换后旧 shotId 已失效，更新应抛错而非静默成功（防止 UI 假"已保存"）。
    func testUpdatePromptForMissingShotThrows() throws {
        let projectId = try repository.createProject(makeProject(title: "Show"))
        let episodeId = try repository.createEpisodeForProject(
            projectId: projectId,
            title: "Ep1",
            content: "content"
        )
        try repository.replaceStoryboards(
            projectId: projectId,
            episodeId: episodeId,
            shots: [makeShot(projectId: projectId, episodeId: episodeId, shotNumber: 1, scene: "s")]
        )

        let stored = try repository.getStoryboards(projectId: projectId, episodeId: episodeId)
        XCTAssertEqual(stored.count, 1)
        try repository.updateShotImagePrompt(shotId: stored[0].id, newPrompt: "new image")
        try repository.updateShotVideoPrompt(shotId: stored[0].id, newPrompt: "new video")
        XCTAssertEqual(try repository.getStoryboards(projectId: projectId, episodeId: episodeId)[0].imagePrompt, "new image")

        XCTAssertThrowsError(
            try repository.updateShotImagePrompt(shotId: stored[0].id + 999, newPrompt: "x")
        )
        XCTAssertThrowsError(
            try repository.updateShotVideoPrompt(shotId: stored[0].id + 999, newPrompt: "x")
        )
    }

    // MARK: - Helpers

    private func makeProject(
        title: String = "Title",
        prompt: String = "Prompt",
        status: ProjectStatus = .draft,
        createdAt: Int64 = 0,
        updatedAt: Int64 = 0
    ) -> DramaProject {
        DramaProject(
            id: 0,
            title: title,
            prompt: prompt,
            style: "cinematic",
            targetAudience: "all",
            aspectRatio: "9:16",
            shotCount: 6,
            shotDurationSeconds: 5,
            status: status,
            currentStage: .none,
            errorMessage: nil,
            generatedScript: nil,
            finalVideoStatus: .pending,
            finalVideoLocalPath: nil,
            finalVideoErrorMessage: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func makeShot(
        projectId: Int64,
        episodeId: Int64,
        shotNumber: Int,
        scene: String,
        characterNames: [String] = []
    ) -> StoryboardShot {
        StoryboardShot(
            id: 0,
            projectId: projectId,
            episodeId: episodeId,
            shotNumber: shotNumber,
            scene: scene,
            action: "action",
            dialogue: "dialogue",
            camera: "camera",
            imagePrompt: "image",
            videoPrompt: "video",
            durationSeconds: 5,
            characterNames: characterNames,
            characterIds: nil,
            imageStatus: .pending,
            imageUrl: nil,
            imageLocalPath: nil,
            imageErrorMessage: nil,
            videoStatus: .pending,
            videoTaskId: nil,
            videoUrl: nil,
            videoLocalPath: nil,
            videoErrorMessage: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }
}
