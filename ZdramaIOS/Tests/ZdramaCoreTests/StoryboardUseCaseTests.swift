import XCTest
@testable import ZdramaCore

final class StoryboardUseCaseTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoryboardUseCaseTests-\(UUID().uuidString)", isDirectory: true)
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

    func testStoryboardFailsWhenOnlyProjectGeneratedScriptSet() async throws {
        let seeded = try seedProject(episodeContent: "raw")
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .completed,
            currentStage: GenerationStage.text,
            generatedScript: "other-episode-script",
            errorMessage: nil
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: storyboardJSON()))
        let useCase = GenerateStoryboardsUseCase(
            repository: repository,
            storyboardRepository: AgnesStoryboardRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "请先为本集创作或改写脚本")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertEqual(project?.generatedScript, "other-episode-script")
        XCTAssertTrue(try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId).isEmpty)
    }

    func testStoryboardSuccessReplacesShotsForEpisode() async throws {
        let seeded = try seedProject(episodeContent: "raw")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "## S01 | 内景\n对白若干",
            status: .completed
        )
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .completed,
            currentStage: GenerationStage.text,
            generatedScript: "keep-me",
            errorMessage: nil
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: storyboardJSON()))
        let useCase = GenerateStoryboardsUseCase(
            repository: repository,
            storyboardRepository: AgnesStoryboardRepository(client: fake)
        )

        let shots = try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(fake.requests.count, 1)
        let stored = try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].episodeId, seeded.episodeId)
        XCTAssertEqual(stored[0].projectId, seeded.projectId)
        XCTAssertEqual(stored[0].scene, "内景")
        XCTAssertEqual(stored[0].action, "走进房间")
        XCTAssertGreaterThan(stored[0].id, 0)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.storyboard)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        XCTAssertNil(project?.errorMessage)
    }

    func testStoryboardFailureDoesNotReplace() async throws {
        let seeded = try seedProject(episodeContent: "raw")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "episode-script",
            status: .completed
        )
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .completed,
            currentStage: GenerationStage.text,
            generatedScript: "keep-me",
            errorMessage: nil
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["error": "boom"], status: 500)
        let useCase = GenerateStoryboardsUseCase(
            repository: repository,
            storyboardRepository: AgnesStoryboardRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Agnes request failed: HTTP 500")
        }

        XCTAssertTrue(try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId).isEmpty)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.storyboard)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        XCTAssertEqual(project?.errorMessage, "Agnes request failed: HTTP 500")
    }

    func testStoryboardMissingProjectThrows() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: storyboardJSON()))
        let useCase = GenerateStoryboardsUseCase(
            repository: repository,
            storyboardRepository: AgnesStoryboardRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(projectId: 99, episodeId: 1, settings: makeSettings())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Project not found")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testStoryboardMissingEpisodeDoesNotFallBack() async throws {
        let seeded = try seedProject(episodeContent: "raw")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "this-episode-script",
            status: .completed
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: storyboardJSON()))
        let useCase = GenerateStoryboardsUseCase(
            repository: repository,
            storyboardRepository: AgnesStoryboardRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId + 99,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Episode not found")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .draft)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
    }

    func testStoryboardBlankEpisodeScriptFailsWithoutHTTP() async throws {
        let seeded = try seedProject(episodeContent: "raw")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "  ",
            status: .completed
        )
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .completed,
            currentStage: GenerationStage.text,
            generatedScript: "project-script",
            errorMessage: nil
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: storyboardJSON()))
        let useCase = GenerateStoryboardsUseCase(
            repository: repository,
            storyboardRepository: AgnesStoryboardRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "请先为本集创作或改写脚本")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    // MARK: - Helpers

    private struct Seeded {
        let projectId: Int64
        let episodeId: Int64
    }

    private func seedProject(episodeContent: String?) throws -> Seeded {
        let projectId = try repository.createProject(
            DramaProject(
                id: 0,
                title: "T",
                prompt: "P",
                style: "cinematic",
                targetAudience: "all",
                aspectRatio: "9:16",
                shotCount: 6,
                shotDurationSeconds: 5,
                status: .draft,
                currentStage: .none,
                errorMessage: nil,
                generatedScript: nil,
                finalVideoStatus: .pending,
                finalVideoLocalPath: nil,
                finalVideoErrorMessage: nil,
                createdAt: 1,
                updatedAt: 1
            )
        )
        let episodeId = try repository.createEpisodeForProject(
            projectId: projectId,
            title: "E1",
            content: episodeContent
        )
        return Seeded(projectId: projectId, episodeId: episodeId)
    }

    private func makeSettings() -> AgnesSettings {
        AgnesSettings(
            apiKey: "sk-test",
            baseUrl: "https://apihub.agnes-ai.com",
            textModel: "agnes-text",
            imageModel: "agnes-image",
            videoModel: "agnes-video",
            requestTimeoutSeconds: 120
        )
    }

    private func chatObject(content: String, finishReason: String = "stop") -> [String: Any] {
        [
            "choices": [[
                "message": ["content": content],
                "finish_reason": finishReason
            ]]
        ]
    }

    private func storyboardJSON() -> String {
        """
        [{"shot_number":"1","scene":"内景","action":"走进房间","dialogue":"你好","camera":"中景","image_prompt":"a room","video_prompt":"walk in","duration_seconds":"5","character_names":["Alice"]}]
        """
    }
}
