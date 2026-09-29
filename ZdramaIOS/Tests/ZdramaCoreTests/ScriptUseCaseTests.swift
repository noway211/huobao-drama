import XCTest
@testable import ZdramaCore

final class ScriptUseCaseTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptUseCaseTests-\(UUID().uuidString)", isDirectory: true)
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

    func testGenerateScriptUsesEpisodeContentNotProjectPrompt() async throws {
        let seeded = try seedProject(
            prompt: "project-only-prompt",
            episodeContent: "episode-story-content"
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "generated-script"))
        let useCase = GenerateProjectScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        let script = try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(script, "generated-script")
        XCTAssertEqual(fake.requests.count, 1)
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages[1]["content"] as? String)
        XCTAssertTrue(user.contains("episode-story-content"), user)
        XCTAssertTrue(user.contains("故事提示词：episode-story-content"), user)
        XCTAssertFalse(user.contains("故事提示词：project-only-prompt"), user)
    }

    func testGenerateScriptSuccessWritesEpisodeAndProject() async throws {
        let seeded = try seedProject(prompt: "P", episodeContent: "raw")
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "final-script"))
        let useCase = GenerateProjectScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        let script = try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(script, "final-script")
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.scriptContent, "final-script")
        XCTAssertEqual(episode?.status, .completed)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.generatedScript, "final-script")
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertNil(project?.errorMessage)
    }

    func testGenerateScriptFailureKeepsPreviousScript() async throws {
        let seeded = try seedProject(prompt: "P", episodeContent: "raw")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "previous-script",
            status: .draft
        )
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .draft,
            currentStage: GenerationStage.none,
            generatedScript: "previous-project-script",
            errorMessage: nil
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["error": "boom"], status: 500)
        let useCase = GenerateProjectScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
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

        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.scriptContent, "previous-script")
        XCTAssertEqual(episode?.status, .failed)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.generatedScript, "previous-script")
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertEqual(project?.errorMessage, "Agnes request failed: HTTP 500")
    }

    func testGenerateScriptMissingProjectThrows() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "unused"))
        let useCase = GenerateProjectScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(projectId: 99, episodeId: 1, settings: makeSettings())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Project not found")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGenerateScriptMissingEpisodeThrows() async throws {
        let projectId = try repository.createProject(makeProject(prompt: "P"))
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "unused"))
        let useCase = GenerateProjectScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: projectId,
                episodeId: 1,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Episode not found")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let project = try repository.getProject(projectId)
        XCTAssertEqual(project?.status, .draft)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
    }

    func testRewriteEmptyContentFailsWithoutHTTP() async throws {
        let seeded = try seedProject(prompt: "P", episodeContent: "   ")
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "should-not-run"))
        let useCase = RewriteEpisodeScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Episode raw content is empty")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.status, .draft)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .draft)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
    }

    func testRewriteNilContentFailsWithoutHTTP() async throws {
        let seeded = try seedProject(prompt: "P", episodeContent: nil)
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "should-not-run"))
        let useCase = RewriteEpisodeScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Episode has no raw content to rewrite")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.status, .draft)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .draft)
    }

    func testRewriteMissingEpisodeThrows() async throws {
        let projectId = try repository.createProject(makeProject(prompt: "P"))
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "unused"))
        let useCase = RewriteEpisodeScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        do {
            _ = try await useCase.execute(
                projectId: projectId,
                episodeId: 1,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Episode not found for project")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testRewriteSuccessWritesCompletedScript() async throws {
        let seeded = try seedProject(prompt: "P", episodeContent: "raw-to-rewrite")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "old-script",
            status: .draft
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "rewritten-script"))
        let useCase = RewriteEpisodeScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        let script = try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(script, "rewritten-script")
        XCTAssertEqual(fake.requests.count, 1)
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages[1]["content"] as? String)
        XCTAssertTrue(user.contains("raw-to-rewrite"), user)
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.scriptContent, "rewritten-script")
        XCTAssertEqual(episode?.status, .completed)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.generatedScript, "rewritten-script")
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertNil(project?.errorMessage)
    }

    func testRewriteFailureKeepsPreviousScript() async throws {
        let seeded = try seedProject(prompt: "P", episodeContent: "raw-to-rewrite")
        try repository.updateEpisodeScriptContent(
            episodeId: seeded.episodeId,
            scriptContent: "previous-rewrite-script",
            status: .draft
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["error": "boom"], status: 500)
        let useCase = RewriteEpisodeScriptUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
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

        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.scriptContent, "previous-rewrite-script")
        XCTAssertEqual(episode?.status, .failed)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.generatedScript, "previous-rewrite-script")
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertEqual(project?.errorMessage, "Agnes request failed: HTTP 500")
    }

    // MARK: - Helpers

    private struct Seeded {
        let projectId: Int64
        let episodeId: Int64
    }

    private func seedProject(prompt: String, episodeContent: String?) throws -> Seeded {
        let projectId = try repository.createProject(makeProject(prompt: prompt))
        let episodeId = try repository.createEpisodeForProject(
            projectId: projectId,
            title: "E1",
            content: episodeContent
        )
        return Seeded(projectId: projectId, episodeId: episodeId)
    }

    private func makeProject(prompt: String) -> DramaProject {
        DramaProject(
            id: 0,
            title: "T",
            prompt: prompt,
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

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}
