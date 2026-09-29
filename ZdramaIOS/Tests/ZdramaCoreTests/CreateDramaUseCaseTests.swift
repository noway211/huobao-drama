import XCTest
@testable import ZdramaCore

final class CreateDramaUseCaseTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreateDramaUseCaseTests-\(UUID().uuidString)", isDirectory: true)
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

    func testExecuteCreatesProjectAndEpisode1WithPromptAsContent() throws {
        let useCase = CreateDramaUseCase(repository: repository)
        let input = CreateDramaInput(
            title: "T",
            prompt: "P",
            style: "cinematic",
            targetAudience: "all",
            aspectRatio: "9:16",
            shotCount: 6,
            shotDurationSeconds: 5
        )

        let projectId = try useCase.execute(input)

        XCTAssertGreaterThan(projectId, 0)

        let project = try repository.getProject(projectId)
        XCTAssertEqual(project?.id, projectId)
        XCTAssertEqual(project?.title, "T")
        XCTAssertEqual(project?.prompt, "P")
        XCTAssertEqual(project?.style, "cinematic")
        XCTAssertEqual(project?.targetAudience, "all")
        XCTAssertEqual(project?.aspectRatio, "9:16")
        XCTAssertEqual(project?.shotCount, 6)
        XCTAssertEqual(project?.shotDurationSeconds, 5)
        XCTAssertEqual(project?.status, .draft)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
        XCTAssertNil(project?.errorMessage)
        XCTAssertNil(project?.generatedScript)
        XCTAssertEqual(project?.finalVideoStatus, .pending)
        XCTAssertNil(project?.finalVideoLocalPath)
        XCTAssertNil(project?.finalVideoErrorMessage)
        XCTAssertGreaterThan(project?.createdAt ?? 0, 0)
        XCTAssertGreaterThan(project?.updatedAt ?? 0, 0)

        let episode = try repository.getEpisodeForProject(projectId)
        XCTAssertEqual(episode?.episodeNumber, 1)
        XCTAssertEqual(episode?.title, "T")
        XCTAssertEqual(episode?.content, "P")
        XCTAssertEqual(episode?.projectId, projectId)
    }
}
