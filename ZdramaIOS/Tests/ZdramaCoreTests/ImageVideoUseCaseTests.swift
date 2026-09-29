import XCTest
@testable import ZdramaCore

final class ImageVideoUseCaseTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!
    private var paths: GeneratedMediaPaths!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageVideoUseCaseTests-\(UUID().uuidString)", isDirectory: true)
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

    func testImagesSkipsCompletedLocalFileAndGeneratesRemainingShotOnce() async throws {
        let seeded = try seedProject()
        let existing = filesRoot.appendingPathComponent("existing-shot.png")
        try Data("already-there".utf8).write(to: existing)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    imagePrompt: "skip-me",
                    imageStatus: .completed,
                    imageUrl: "https://cdn.example/old.png",
                    imageLocalPath: existing.path
                ),
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 2,
                    imagePrompt: "generate-me"
                )
            ]
        )
        let shots = try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertEqual(shots.count, 2)
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [["url": "https://cdn.example/a.png"]]])
        fake.enqueueData(Data("png-bytes".utf8))
        let useCase = GenerateStoryboardImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(fake.requests.count, 2)
        XCTAssertEqual(fake.requests[0].httpMethod, "POST")
        XCTAssertEqual(
            fake.requests[0].url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/images/generations"
        )
        let body = try requestJSON(fake.requests[0])
        XCTAssertEqual(body["prompt"] as? String, "generate-me")
        XCTAssertEqual(fake.requests[1].httpMethod, "GET")
        XCTAssertEqual(fake.requests[1].url?.absoluteString, "https://cdn.example/a.png")

        let stored = try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertEqual(stored[0].imageStatus, .completed)
        XCTAssertEqual(stored[0].imageLocalPath, existing.path)
        XCTAssertEqual(stored[1].imageStatus, .completed)
        XCTAssertEqual(stored[1].imageUrl, "https://cdn.example/a.png")
        XCTAssertEqual(
            stored[1].imageLocalPath,
            paths.shotImage(projectId: seeded.projectId, shotId: stored[1].id, ext: "png").path
        )
        XCTAssertEqual(try String(contentsOfFile: stored[1].imageLocalPath ?? "", encoding: .utf8), "png-bytes")
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.image)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        XCTAssertNil(project?.errorMessage)
    }

    func testImagesFailFastMarksSecondFailedAndDoesNotContinue() async throws {
        let seeded = try seedProject()
        let existing = filesRoot.appendingPathComponent("keep-completed.png")
        try Data("keep".utf8).write(to: existing)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    imagePrompt: "already-done",
                    imageStatus: .completed,
                    imageUrl: "https://cdn.example/old.png",
                    imageLocalPath: existing.path
                ),
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 2,
                    imagePrompt: "will-fail",
                    imageUrl: "https://cdn.example/prev.png",
                    imageLocalPath: "/tmp/prev.png"
                )
            ]
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["error": "boom"], status: 500)
        let useCase = GenerateStoryboardImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Agnes request failed: HTTP 500")
        }

        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertEqual(
            fake.requests[0].url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/images/generations"
        )
        let stored = try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertEqual(stored[0].imageStatus, .completed)
        XCTAssertEqual(stored[0].imageLocalPath, existing.path)
        XCTAssertEqual(stored[1].imageStatus, .failed)
        XCTAssertEqual(stored[1].imageUrl, "https://cdn.example/prev.png")
        XCTAssertEqual(stored[1].imageLocalPath, "/tmp/prev.png")
        XCTAssertEqual(stored[1].imageErrorMessage, "Agnes request failed: HTTP 500")
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.image)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        XCTAssertEqual(project?.errorMessage, "Agnes request failed: HTTP 500")
    }

    func testImagesEmptyStoryboardsThrowsBeforeHTTP() async throws {
        let seeded = try seedProject()
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [["url": "https://cdn.example/a.png"]]])
        let useCase = GenerateStoryboardImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Generate storyboards before images")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .draft)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
        XCTAssertEqual(project?.generatedScript, "keep-me")
    }

    func testImagesMissingProjectThrows() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [["url": "https://cdn.example/a.png"]]])
        let useCase = GenerateStoryboardImagesUseCase(
            repository: repository,
            imageRepository: AgnesImageRepository(client: fake),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            try await useCase.execute(projectId: 99, episodeId: 1, settings: makeSettings())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Project not found")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testVideosSkipsCompletedLocalFileAndGeneratesRemainingShotOnce() async throws {
        let seeded = try seedProject()
        let existing = filesRoot.appendingPathComponent("existing-shot.mp4")
        try Data("already-video".utf8).write(to: existing)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    videoStatus: .completed,
                    videoUrl: "https://cdn.example/old.mp4",
                    videoLocalPath: existing.path
                ),
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 2,
                    imageUrl: "https://cdn.example/ref.png"
                )
            ]
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject([
            "status": "completed",
            "id": "id-1",
            "video_url": "https://cdn.example/now.mp4"
        ])
        fake.enqueueData(Data("mp4-bytes".utf8))
        let useCase = GenerateStoryboardVideosUseCase(
            repository: repository,
            videoRepository: AgnesVideoRepository(client: fake, sleep: { _ in }),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        XCTAssertEqual(fake.requests.count, 2)
        XCTAssertEqual(fake.requests[0].httpMethod, "POST")
        XCTAssertEqual(
            fake.requests[0].url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/videos"
        )
        let body = try requestJSON(fake.requests[0])
        XCTAssertEqual(body["image"] as? String, "https://cdn.example/ref.png")
        XCTAssertEqual(fake.requests[1].httpMethod, "GET")
        XCTAssertEqual(fake.requests[1].url?.absoluteString, "https://cdn.example/now.mp4")

        let stored = try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertEqual(stored[0].videoStatus, .completed)
        XCTAssertEqual(stored[0].videoLocalPath, existing.path)
        XCTAssertEqual(stored[1].videoStatus, .completed)
        XCTAssertEqual(stored[1].videoTaskId, "id-1")
        XCTAssertEqual(stored[1].videoUrl, "https://cdn.example/now.mp4")
        XCTAssertEqual(
            stored[1].videoLocalPath,
            paths.shotVideo(projectId: seeded.projectId, shotId: stored[1].id, ext: "mp4").path
        )
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.video)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        XCTAssertNil(project?.errorMessage)
    }

    func testVideosUsesDataURIWhenLocalImageExists() async throws {
        let seeded = try seedProject()
        let imageFile = filesRoot.appendingPathComponent("ref.png")
        try Data("png-bytes".utf8).write(to: imageFile)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    imageUrl: "https://cdn.example/ignored.png",
                    imageLocalPath: imageFile.path
                )
            ]
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject([
            "status": "completed",
            "id": "id-1",
            "video_url": "https://cdn.example/now.mp4"
        ])
        fake.enqueueData(Data("mp4-bytes".utf8))
        let useCase = GenerateStoryboardVideosUseCase(
            repository: repository,
            videoRepository: AgnesVideoRepository(client: fake, sleep: { _ in }),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        try await useCase.execute(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            settings: makeSettings()
        )

        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        let expected = "data:image/png;base64,\(Data("png-bytes".utf8).base64EncodedString())"
        XCTAssertEqual(body["image"] as? String, expected)
    }

    func testVideosFailFastMarksSecondFailedAndDoesNotContinue() async throws {
        let seeded = try seedProject()
        let existing = filesRoot.appendingPathComponent("keep-video.mp4")
        try Data("keep".utf8).write(to: existing)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    videoStatus: .completed,
                    videoUrl: "https://cdn.example/old.mp4",
                    videoLocalPath: existing.path
                ),
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 2,
                    imageUrl: "https://cdn.example/ref.png",
                    videoUrl: "https://cdn.example/prev.mp4",
                    videoLocalPath: "/tmp/prev.mp4"
                )
            ]
        )
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["error": "boom"], status: 500)
        let useCase = GenerateStoryboardVideosUseCase(
            repository: repository,
            videoRepository: AgnesVideoRepository(client: fake, sleep: { _ in }),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Agnes request failed: HTTP 500")
        }

        XCTAssertEqual(fake.requests.count, 1)
        let stored = try repository.getStoryboards(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertEqual(stored[0].videoStatus, .completed)
        XCTAssertEqual(stored[1].videoStatus, .failed)
        XCTAssertEqual(stored[1].videoUrl, "https://cdn.example/prev.mp4")
        XCTAssertEqual(stored[1].videoLocalPath, "/tmp/prev.mp4")
        XCTAssertEqual(stored[1].videoErrorMessage, "Agnes request failed: HTTP 500")
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.video)
        XCTAssertEqual(project?.errorMessage, "Agnes request failed: HTTP 500")
        XCTAssertEqual(project?.generatedScript, "keep-me")
    }

    func testVideosEmptyStoryboardsThrowsBeforeHTTP() async throws {
        let seeded = try seedProject()
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject([
            "status": "completed",
            "id": "id-1",
            "video_url": "https://cdn.example/now.mp4"
        ])
        let useCase = GenerateStoryboardVideosUseCase(
            repository: repository,
            videoRepository: AgnesVideoRepository(client: fake, sleep: { _ in }),
            downloadRepository: MediaDownloadRepository(client: fake, paths: paths)
        )

        do {
            try await useCase.execute(
                projectId: seeded.projectId,
                episodeId: seeded.episodeId,
                settings: makeSettings()
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Generate storyboards before videos")
        }
        XCTAssertTrue(fake.requests.isEmpty)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .draft)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
    }

    func testComposeEmptyStoryboardsThrowsAfterMarkFailed() async throws {
        let seeded = try seedProject()
        let useCase = ComposeFinalVideoUseCase(
            dramaRepository: repository,
            composer: FakeMp4Composer(),
            paths: paths
        )

        do {
            _ = try await useCase.execute(projectId: seeded.projectId, episodeId: seeded.episodeId)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "请先生成分镜")
        }

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.finalVideo)
        XCTAssertEqual(project?.finalVideoStatus, .failed)
        XCTAssertNil(project?.finalVideoLocalPath)
        XCTAssertEqual(project?.finalVideoErrorMessage, "请先生成分镜")
        XCTAssertEqual(project?.errorMessage, "请先生成分镜")
        XCTAssertEqual(project?.generatedScript, "keep-me")
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.finalVideoStatus, .failed)
        XCTAssertNil(episode?.finalVideoLocalPath)
        XCTAssertEqual(episode?.finalVideoErrorMessage, "请先生成分镜")
    }

    func testComposeMissingLocalVideosThrowsAfterMarkFailed() async throws {
        let seeded = try seedProject()
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    videoStatus: .completed,
                    videoLocalPath: filesRoot.appendingPathComponent("missing.mp4").path
                )
            ]
        )
        let useCase = ComposeFinalVideoUseCase(
            dramaRepository: repository,
            composer: FakeMp4Composer(),
            paths: paths
        )

        do {
            _ = try await useCase.execute(projectId: seeded.projectId, episodeId: seeded.episodeId)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "请先生成并下载全部分镜视频后再合成成片")
        }

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.finalVideo)
        XCTAssertEqual(project?.finalVideoStatus, .failed)
        XCTAssertNil(project?.finalVideoLocalPath)
        XCTAssertEqual(project?.errorMessage, "请先生成并下载全部分镜视频后再合成成片")
        XCTAssertEqual(project?.generatedScript, "keep-me")
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.finalVideoStatus, .failed)
        XCTAssertNil(episode?.finalVideoLocalPath)
        XCTAssertEqual(episode?.finalVideoErrorMessage, "请先生成并下载全部分镜视频后再合成成片")
    }

    func testComposeSuccessWritesFinalVideoAndMarksCompleted() async throws {
        let seeded = try seedProject()
        let video1 = filesRoot.appendingPathComponent("shot1.mp4")
        let video2 = filesRoot.appendingPathComponent("shot2.mp4")
        try Data("v1".utf8).write(to: video1)
        try Data("v2".utf8).write(to: video2)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    videoStatus: .completed,
                    videoLocalPath: video1.path
                ),
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 2,
                    videoStatus: .completed,
                    videoLocalPath: video2.path
                )
            ]
        )
        let expectedPath = paths.finalVideo(projectId: seeded.projectId, episodeId: seeded.episodeId).path
        let composer = FakeMp4Composer()
        let useCase = ComposeFinalVideoUseCase(
            dramaRepository: repository,
            composer: composer,
            paths: paths
        )

        let output = try await useCase.execute(projectId: seeded.projectId, episodeId: seeded.episodeId)

        XCTAssertEqual(output, expectedPath)
        XCTAssertEqual(try String(contentsOfFile: expectedPath, encoding: .utf8), "fake-mp4")
        XCTAssertEqual(composer.lastInputPaths, [video1.path, video2.path])
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.finalVideo)
        XCTAssertEqual(project?.finalVideoStatus, .completed)
        XCTAssertEqual(project?.finalVideoLocalPath, expectedPath)
        XCTAssertNil(project?.finalVideoErrorMessage)
        XCTAssertNil(project?.errorMessage)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.finalVideoStatus, .completed)
        XCTAssertEqual(episode?.finalVideoLocalPath, expectedPath)
        XCTAssertNil(episode?.finalVideoErrorMessage)
    }

    func testComposeMissingProjectThrows() async {
        let useCase = ComposeFinalVideoUseCase(
            dramaRepository: repository,
            composer: FakeMp4Composer(),
            paths: paths
        )

        do {
            _ = try await useCase.execute(projectId: 99, episodeId: 1)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "项目不存在")
        }
    }

    func testComposeComposerFailureMarksFailedAndRethrows() async throws {
        let seeded = try seedProject()
        let video1 = filesRoot.appendingPathComponent("shot1.mp4")
        try Data("v1".utf8).write(to: video1)
        try repository.replaceStoryboards(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            shots: [
                makeShot(
                    projectId: seeded.projectId,
                    episodeId: seeded.episodeId,
                    shotNumber: 1,
                    videoStatus: .completed,
                    videoLocalPath: video1.path
                )
            ]
        )
        let useCase = ComposeFinalVideoUseCase(
            dramaRepository: repository,
            composer: FakeMp4Composer(error: LocalizedMessageError("compose failed")),
            paths: paths
        )

        do {
            _ = try await useCase.execute(projectId: seeded.projectId, episodeId: seeded.episodeId)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "compose failed")
        }

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.finalVideo)
        XCTAssertEqual(project?.finalVideoStatus, .failed)
        XCTAssertNil(project?.finalVideoLocalPath)
        XCTAssertEqual(project?.finalVideoErrorMessage, "compose failed")
        XCTAssertEqual(project?.errorMessage, "compose failed")
        XCTAssertEqual(project?.generatedScript, "keep-me")
        let episode = try repository.getEpisodeById(seeded.episodeId)
        XCTAssertEqual(episode?.finalVideoStatus, .failed)
        XCTAssertNil(episode?.finalVideoLocalPath)
        XCTAssertEqual(episode?.finalVideoErrorMessage, "compose failed")
    }

    // MARK: - Helpers

    private struct Seeded {
        let projectId: Int64
        let episodeId: Int64
    }

    private func seedProject() throws -> Seeded {
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
                generatedScript: "keep-me",
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
            content: "raw"
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

    private func makeShot(
        projectId: Int64,
        episodeId: Int64,
        shotNumber: Int,
        imagePrompt: String = "image-prompt",
        videoPrompt: String = "video-prompt",
        imageStatus: AssetStatus = .pending,
        imageUrl: String? = nil,
        imageLocalPath: String? = nil,
        videoStatus: AssetStatus = .pending,
        videoUrl: String? = nil,
        videoLocalPath: String? = nil
    ) -> StoryboardShot {
        StoryboardShot(
            id: 0,
            projectId: projectId,
            episodeId: episodeId,
            shotNumber: shotNumber,
            scene: "scene",
            action: "action",
            dialogue: "dialogue",
            camera: "camera",
            imagePrompt: imagePrompt,
            videoPrompt: videoPrompt,
            durationSeconds: 5,
            characterNames: [],
            characterIds: nil,
            imageStatus: imageStatus,
            imageUrl: imageUrl,
            imageLocalPath: imageLocalPath,
            imageErrorMessage: nil,
            videoStatus: videoStatus,
            videoTaskId: nil,
            videoUrl: videoUrl,
            videoLocalPath: videoLocalPath,
            videoErrorMessage: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}

private final class FakeMp4Composer: Mp4Composing, @unchecked Sendable {
    private let error: Error?
    private(set) var lastInputPaths: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func compose(inputPaths: [String], outputPath: String) async throws -> String {
        lastInputPaths = inputPaths
        if let error {
            throw error
        }
        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake-mp4".utf8).write(to: url)
        return outputPath
    }
}
