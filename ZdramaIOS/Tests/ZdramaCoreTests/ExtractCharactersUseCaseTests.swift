import XCTest
@testable import ZdramaCore

final class ExtractCharactersUseCaseTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtractCharactersUseCaseTests-\(UUID().uuidString)", isDirectory: true)
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

    func testExtractRequiresEpisodeScript() async throws {
        let seeded = try seedProject(scriptContent: "   ")
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .completed,
            currentStage: .text,
            generatedScript: "project-script-must-not-be-used",
            errorMessage: nil
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "[]"))
        let useCase = ExtractCharactersUseCase(
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
            XCTAssertEqual(error.localizedDescription, "请先为本集创作或改写脚本")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testExtractMergesSameNameAndKeepsPortrait() async throws {
        let seeded = try seedProject(scriptContent: "沈惊川推门而入，林晚站在窗边。")
        try repository.upsertCharacters(projectId: seeded.projectId, characters: [
            makeCharacter(
                name: "沈惊川",
                role: "男主",
                description: "旧描述",
                appearance: "旧外貌",
                personality: "旧性格",
                imageStatus: .completed,
                imageUrl: "https://img/shen",
                imageLocalPath: "/portraits/shen.jpg",
                imageErrorMessage: "旧错误"
            )
        ])
        let existingId = try XCTUnwrap(try repository.getCharacters(projectId: seeded.projectId).first?.id)
        let reply = """
        提取结果如下：
        [{"name":"沈惊川","role":"","description":"","appearance":"新外貌","personality":"冷静","existing_id":\(existingId)},{"name":" 林晚 ","role":"女主","description":"窗边","appearance":"白衣","personality":""},{"name":"  ","role":"龙套"}]
        以上。
        """
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: reply))
        let useCase = ExtractCharactersUseCase(
            repository: repository,
            textRepository: AgnesTextRepository(client: fake)
        )

        let count = try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(count, 2)
        let rows = try repository.getCharacters(projectId: seeded.projectId)
        XCTAssertEqual(rows.map(\.name), ["沈惊川", "林晚"])
        let shen = try XCTUnwrap(rows.first { $0.id == existingId })
        XCTAssertEqual(shen.imageStatus, .completed)
        XCTAssertEqual(shen.imageLocalPath, "/portraits/shen.jpg")
        XCTAssertEqual(shen.imageUrl, "https://img/shen")
        XCTAssertEqual(shen.imageErrorMessage, "旧错误")
        XCTAssertEqual(shen.appearance, "新外貌")
        XCTAssertEqual(shen.role, "男主")
        XCTAssertEqual(shen.description, "旧描述")
        XCTAssertEqual(shen.personality, "冷静")
        let lin = try XCTUnwrap(rows.first { $0.name == "林晚" })
        XCTAssertEqual(lin.role, "女主")
        XCTAssertEqual(lin.appearance, "白衣")
        XCTAssertNotEqual(lin.id, existingId)

        XCTAssertEqual(fake.requests.count, 1)
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual(body["temperature"] as? Double, 0.3)
        XCTAssertEqual(body["max_tokens"] as? Int, 4000)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages[1]["content"] as? String)
        XCTAssertTrue(user.contains("项目中已存在角色：沈惊川。"), user)
        XCTAssertTrue(user.contains("existing_id"), user)
        XCTAssertTrue(user.contains("沈惊川推门而入"), user)
        XCTAssertFalse(user.contains("project-script"), user)
    }

    func testExtractRejectsUnparseableReply() async throws {
        let seeded = try seedProject(scriptContent: "只有对白，没有角色表。")
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "抱歉，我无法提取。"))
        let useCase = ExtractCharactersUseCase(
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
            XCTAssertEqual(error.localizedDescription, "无法解析角色提取结果")
        }
        XCTAssertTrue(try repository.getCharacters(projectId: seeded.projectId).isEmpty)
    }

    private struct Seeded {
        let projectId: Int64
        let episodeId: Int64
    }

    private func seedProject(scriptContent: String?) throws -> Seeded {
        let projectId = try repository.createProject(makeProject())
        let episodeId = try repository.createEpisodeForProject(projectId: projectId, title: "E1", content: "raw")
        try repository.updateEpisodeScriptContent(
            episodeId: episodeId,
            scriptContent: scriptContent,
            status: .completed
        )
        return Seeded(projectId: projectId, episodeId: episodeId)
    }

    private func makeProject() -> DramaProject {
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
    }

    private func makeCharacter(
        name: String,
        role: String,
        description: String,
        appearance: String,
        personality: String,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ) -> Character {
        Character(
            id: 0,
            projectId: 0,
            episodeId: nil,
            name: name,
            role: role,
            description: description,
            appearance: appearance,
            personality: personality,
            imageStatus: imageStatus,
            imageUrl: imageUrl,
            imageLocalPath: imageLocalPath,
            imageErrorMessage: imageErrorMessage,
            createdAt: 0,
            updatedAt: 0
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

    private func chatObject(content: String) -> [String: Any] {
        ["choices": [["message": ["content": content], "finish_reason": "stop"]]]
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}
