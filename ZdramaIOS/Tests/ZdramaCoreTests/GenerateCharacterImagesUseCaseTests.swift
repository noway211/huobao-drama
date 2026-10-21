import XCTest
@testable import ZdramaCore

final class GenerateCharacterImagesUseCaseTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!
    private var paths: GeneratedMediaPaths!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenerateCharacterImagesUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        repository = DramaRepository(db: db, filesRoot: filesRoot)
        paths = GeneratedMediaPaths(root: filesRoot)
    }

    override func tearDownWithError() throws {
        repository = nil
        paths = nil
        if let filesRoot {
            try? FileManager.default.removeItem(at: filesRoot)
        }
        filesRoot = nil
    }

    func testBatchSkipsCompletedFileAndContinuesAfterFailure() async throws {
        let projectId = try seedProject()
        let existing = filesRoot.appendingPathComponent("shen.png")
        try Data("already".utf8).write(to: existing)
        try repository.upsertCharacters(projectId: projectId, characters: [
            makeCharacter(name: "沈惊川", appearance: "黑衣", imageStatus: .completed, imageLocalPath: existing.path),
            makeCharacter(name: "林晚", description: "窗边", imageStatus: .pending, imageLocalPath: nil)
        ])
        let rows = try repository.getCharacters(projectId: projectId)
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["error": "boom"], status: 500)
        let useCase = GenerateCharacterImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            _ = try await useCase.execute(
                projectId: projectId,
                episodeId: 1,
                settings: makeSettings(),
                forceRegenerate: false
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Agnes request failed: HTTP 500")
        }

        XCTAssertEqual(fake.requests.count, 1)
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual(body["prompt"] as? String, "林晚, 窗边, high quality, front-facing portrait")
        let stored = try repository.getCharacters(projectId: projectId)
        XCTAssertEqual(stored.first { $0.id == rows[0].id }?.imageStatus, .completed)
        XCTAssertEqual(stored.first { $0.id == rows[0].id }?.imageLocalPath, existing.path)
        XCTAssertEqual(stored.first { $0.id == rows[1].id }?.imageStatus, .failed)
        XCTAssertEqual(stored.first { $0.id == rows[1].id }?.imageErrorMessage, "Agnes request failed: HTTP 500")
    }

    func testBatchForceRegenerateRedrawsCompletedFile() async throws {
        let projectId = try seedProject()
        let existing = filesRoot.appendingPathComponent("shen.png")
        try Data("already".utf8).write(to: existing)
        try repository.upsertCharacters(projectId: projectId, characters: [
            makeCharacter(name: "沈惊川", appearance: "黑衣", imageStatus: .completed, imageLocalPath: existing.path)
        ])
        let characterId = try XCTUnwrap(try repository.getCharacters(projectId: projectId).first?.id)
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [["url": "https://cdn.example/shen.png"]]])
        fake.enqueueData(Data("png-bytes".utf8))
        let useCase = GenerateCharacterImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        let generated = try await useCase.execute(
            projectId: projectId,
            episodeId: 9,
            settings: makeSettings(),
            forceRegenerate: true
        )

        XCTAssertEqual(generated, 1)
        XCTAssertEqual(fake.requests.count, 2)
        let body = try requestJSON(fake.requests[0])
        XCTAssertEqual(body["prompt"] as? String, "沈惊川, 黑衣, high quality, front-facing portrait")
        let stored = try XCTUnwrap(try repository.getCharacters(projectId: projectId).first)
        XCTAssertEqual(stored.imageStatus, .completed)
        XCTAssertEqual(
            stored.imageLocalPath,
            paths.characterImage(projectId: projectId, characterId: characterId, ext: "png").path
        )
        XCTAssertEqual(try String(contentsOfFile: stored.imageLocalPath ?? "", encoding: .utf8), "png-bytes")
    }

    func testBatchRequiresCharacters() async throws {
        let projectId = try seedProject()
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [["url": "https://cdn.example/a.png"]]])
        let useCase = GenerateCharacterImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            _ = try await useCase.execute(
                projectId: projectId,
                episodeId: 1,
                settings: makeSettings(),
                forceRegenerate: false
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "请先提取角色")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testSingleRedrawMarksFailed() async throws {
        let projectId = try seedProject()
        try repository.upsertCharacters(projectId: projectId, characters: [
            makeCharacter(name: "无名", appearance: "", imageStatus: .pending, imageLocalPath: nil)
        ])
        let characterId = try XCTUnwrap(try repository.getCharacters(projectId: projectId).first?.id)
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [[:]]])
        let useCase = GenerateSingleCharacterImageUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            _ = try await useCase.execute(projectId: projectId, characterId: characterId, settings: makeSettings())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "No image URL in Agnes response")
        }
        let stored = try XCTUnwrap(try repository.getCharacters(projectId: projectId).first)
        XCTAssertEqual(stored.imageStatus, .failed)
        XCTAssertEqual(stored.imageErrorMessage, "No image URL in Agnes response")
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual(body["prompt"] as? String, "无名, character portrait, high quality, front-facing portrait")
    }

    private func seedProject() throws -> Int64 {
        try repository.createProject(
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
    }

    private func makeCharacter(
        name: String,
        appearance: String = "",
        description: String = "",
        imageStatus: AssetStatus,
        imageLocalPath: String?
    ) -> Character {
        Character(
            id: 0,
            projectId: 0,
            episodeId: nil,
            name: name,
            role: "",
            description: description,
            appearance: appearance,
            personality: "",
            imageStatus: imageStatus,
            imageUrl: nil,
            imageLocalPath: imageLocalPath,
            imageErrorMessage: nil,
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

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}
