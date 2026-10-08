import XCTest
@testable import ZdramaCore

final class GenerationCoordinatorTests: XCTestCase {
    private var filesRoot: URL!
    private var repository: DramaRepository!
    private var paths: GeneratedMediaPaths!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settingsStore: AgnesSettingsStore!

    override func setUpWithError() throws {
        let db = try DramaDatabase.openInMemory()
        filesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenerationCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        repository = DramaRepository(db: db, filesRoot: filesRoot)
        paths = GeneratedMediaPaths(root: filesRoot)
        suiteName = "GenerationCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
        settingsStore = AgnesSettingsStore(defaults: defaults, keychain: InMemoryKeychainStore())
        try settingsStore.save(
            AgnesSettings(
                apiKey: "sk-test",
                baseUrl: "https://apihub.agnes-ai.com",
                textModel: "agnes-text",
                imageModel: "agnes-image",
                videoModel: "agnes-video",
                requestTimeoutSeconds: 120
            )
        )
    }

    override func tearDownWithError() throws {
        repository = nil
        paths = nil
        settingsStore = nil
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        if let filesRoot {
            try? FileManager.default.removeItem(at: filesRoot)
        }
        filesRoot = nil
    }

    func testDoubleEnqueueTextStartsOnce() async throws {
        let seeded = try seedProject()
        let http = WaitingAgnesHTTPClient()
        let coordinator = makeCoordinator(http: http)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: GenerationStageKey.text,
            forceRegenerate: false
        )
        await http.waitForRequestCount(1)
        let runningBeforeDuplicate = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertTrue(runningBeforeDuplicate)
        XCTAssertEqual(http.requestCount, 1)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: GenerationStageKey.text,
            forceRegenerate: false
        )
        XCTAssertEqual(http.requestCount, 1)
        let runningAfterDuplicate = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertTrue(runningAfterDuplicate)

        http.resumeJSONObject(chatObject(content: "generated-script"))
        try await waitForProjectStatus(.completed, projectId: seeded.projectId)
        let runningAfterCompletion = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertFalse(runningAfterCompletion)

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertEqual(project?.generatedScript, "generated-script")
        XCTAssertEqual(http.requestCount, 1)
    }

    func testForceRegenerateCancelsFirstAndStartsSecond() async throws {
        let seeded = try seedProject()
        let http = WaitingAgnesHTTPClient()
        let coordinator = makeCoordinator(http: http)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: GenerationStageKey.text,
            forceRegenerate: false
        )
        await http.waitForRequestCount(1)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: GenerationStageKey.text,
            forceRegenerate: true
        )
        await http.waitForRequestCount(2)
        let running = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertTrue(running)

        http.resumeJSONObject(chatObject(content: "second-script"))
        try await waitForProjectStatus(.completed, projectId: seeded.projectId)
        let runningAfterCompletion = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertFalse(runningAfterCompletion)

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .completed)
        XCTAssertNotEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertEqual(project?.generatedScript, "second-script")
        XCTAssertEqual(http.requestCount, 2)
    }

    func testFullStopsWhenScriptThrowsWithoutStoryboardHTTP() async throws {
        let seeded = try seedProject()
        let http = WaitingAgnesHTTPClient()
        http.enqueueJSONObject(["error": "boom"], status: 500)
        let coordinator = makeCoordinator(http: http)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: GenerationStageKey.full,
            forceRegenerate: false
        )
        try await waitForProjectStatus(.failed, projectId: seeded.projectId)
        let running = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertFalse(running)

        XCTAssertEqual(http.requestCount, 1)
        XCTAssertEqual(
            http.requests.first?.url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/chat/completions"
        )

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.text)
        XCTAssertEqual(project?.errorMessage, "Agnes request failed: HTTP 500")
    }

    func testCancelMidWaitLeavesProjectCancelled() async throws {
        let seeded = try seedProject()
        let http = WaitingAgnesHTTPClient()
        let coordinator = makeCoordinator(http: http)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: GenerationStageKey.text,
            forceRegenerate: false
        )
        await http.waitForRequestCount(1)
        let runningBeforeCancel = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertTrue(runningBeforeCancel)

        await coordinator.cancel(projectId: seeded.projectId, episodeId: seeded.episodeId)

        let runningAfterCancel = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertFalse(runningAfterCancel)
        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .cancelled)
        XCTAssertNotEqual(project?.status, .failed)
    }

    func testUnknownStageMarksFailedWithoutHTTP() async throws {
        let seeded = try seedProject()
        try repository.updateProjectTextResult(
            projectId: seeded.projectId,
            status: .draft,
            currentStage: GenerationStage.none,
            generatedScript: "keep-me",
            errorMessage: nil
        )
        let http = WaitingAgnesHTTPClient()
        let coordinator = makeCoordinator(http: http)

        await coordinator.enqueue(
            projectId: seeded.projectId,
            episodeId: seeded.episodeId,
            stage: "bogus",
            forceRegenerate: false
        )
        try await waitForProjectStatus(.failed, projectId: seeded.projectId)
        let running = await coordinator.isRunning(projectId: seeded.projectId, episodeId: seeded.episodeId)
        XCTAssertFalse(running)

        let project = try repository.getProject(seeded.projectId)
        XCTAssertEqual(project?.status, .failed)
        XCTAssertEqual(project?.currentStage, GenerationStage.none)
        XCTAssertEqual(project?.generatedScript, "keep-me")
        XCTAssertEqual(project?.errorMessage, "Unknown generation stage: bogus")
        XCTAssertEqual(http.requestCount, 0)
    }

    func testMismatchedEpisodeDoesNotStartJobOrChangeProject() async throws {
        let first = try seedProject()
        let second = try seedProject()
        let http = WaitingAgnesHTTPClient()
        let coordinator = makeCoordinator(http: http)

        await coordinator.enqueue(
            projectId: first.projectId,
            episodeId: second.episodeId,
            stage: GenerationStageKey.text,
            forceRegenerate: false
        )
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(http.requestCount, 0)
        let running = await coordinator.isRunning(projectId: first.projectId, episodeId: second.episodeId)
        XCTAssertFalse(running)
        XCTAssertEqual(try repository.getProject(first.projectId)?.status, .draft)
        XCTAssertEqual(try repository.getProject(second.projectId)?.status, .draft)
    }

    // MARK: - Helpers

    private struct Seeded {
        let projectId: Int64
        let episodeId: Int64
    }

    private func seedProject() throws -> Seeded {
        let projectId = try CreateDramaUseCase(repository: repository).execute(
            CreateDramaInput(
                title: "T",
                prompt: "episode-story",
                style: "cinematic",
                targetAudience: "all",
                aspectRatio: "9:16",
                shotCount: 6,
                shotDurationSeconds: 5
            )
        )
        let episode = try XCTUnwrap(repository.getEpisodeForProject(projectId))
        return Seeded(projectId: projectId, episodeId: episode.id)
    }

    private func makeCoordinator(http: AgnesHTTPClient) -> GenerationCoordinator {
        let download = MediaDownloadRepository(client: http, paths: paths)
        return GenerationCoordinator(
            settingsStore: settingsStore,
            repository: repository,
            scriptUseCase: GenerateProjectScriptUseCase(
                repository: repository,
                textRepository: AgnesTextRepository(client: http)
            ),
            rewriteUseCase: RewriteEpisodeScriptUseCase(
                repository: repository,
                textRepository: AgnesTextRepository(client: http)
            ),
            storyboardUseCase: GenerateStoryboardsUseCase(
                repository: repository,
                storyboardRepository: AgnesStoryboardRepository(client: http)
            ),
            imageUseCase: GenerateStoryboardImagesUseCase(
                repository: repository,
                imageRepository: AgnesImageRepository(client: http),
                downloadRepository: download
            ),
            videoUseCase: GenerateStoryboardVideosUseCase(
                repository: repository,
                videoRepository: AgnesVideoRepository(client: http, sleep: { _ in }),
                downloadRepository: download
            ),
            composeUseCase: ComposeFinalVideoUseCase(
                dramaRepository: repository,
                composer: LocalMp4Composer(),
                paths: paths
            )
        )
    }

    private func waitForProjectStatus(_ expected: ProjectStatus, projectId: Int64) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if try repository.getProject(projectId)?.status == expected {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let actual = try repository.getProject(projectId)?.status
        XCTFail("timed out waiting for \(expected.rawValue), last status \(actual?.rawValue ?? "nil")")
    }

    private func chatObject(content: String, finishReason: String = "stop") -> [String: Any] {
        [
            "choices": [[
                "message": ["content": content],
                "finish_reason": finishReason
            ]]
        ]
    }
}

private final class WaitingAgnesHTTPClient: AgnesHTTPClient, @unchecked Sendable {
    private struct QueuedResponse {
        var data: Data
        var status: Int
    }

    private struct PendingSend {
        var id: UUID
        var request: URLRequest
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var pending: [PendingSend] = []
    private var queued: [QueuedResponse] = []
    private var cancelledBeforeRegister: Set<UUID> = []
    private var requestCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requests.count
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func enqueueJSONObject(_ object: Any, status: Int = 200) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        fulfillOrQueue(data: data, status: status)
    }

    func resumeJSONObject(_ object: Any, status: Int = 200) {
        enqueueJSONObject(object, status: status)
    }

    func waitForRequestCount(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if _requests.count >= count {
                lock.unlock()
                continuation.resume()
                return
            }
            requestCountWaiters.append((count, continuation))
            lock.unlock()
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                _requests.append(request)
                let readyWaiters = takeReadyWaitersLocked()
                if cancelledBeforeRegister.remove(id) != nil {
                    lock.unlock()
                    readyWaiters.forEach { $0.resume() }
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if queued.isEmpty {
                    pending.append(PendingSend(id: id, request: request, continuation: continuation))
                    lock.unlock()
                    readyWaiters.forEach { $0.resume() }
                    return
                }
                let response = queued.removeFirst()
                lock.unlock()
                readyWaiters.forEach { $0.resume() }
                continuation.resume(returning: makeResponse(request: request, data: response.data, status: response.status))
            }
        } onCancel: { [self] in
            lock.lock()
            if let index = pending.firstIndex(where: { $0.id == id }) {
                let send = pending.remove(at: index)
                lock.unlock()
                send.continuation.resume(throwing: CancellationError())
            } else {
                cancelledBeforeRegister.insert(id)
                lock.unlock()
            }
        }
    }

    private func fulfillOrQueue(data: Data, status: Int) {
        lock.lock()
        if pending.isEmpty {
            queued.append(QueuedResponse(data: data, status: status))
            lock.unlock()
            return
        }
        let send = pending.removeFirst()
        lock.unlock()
        send.continuation.resume(returning: makeResponse(request: send.request, data: data, status: status))
    }

    private func takeReadyWaitersLocked() -> [CheckedContinuation<Void, Never>] {
        let count = _requests.count
        let ready = requestCountWaiters.filter { $0.0 <= count }.map(\.1)
        requestCountWaiters.removeAll { $0.0 <= count }
        return ready
    }

    private func makeResponse(request: URLRequest, data: Data, status: Int) -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}
