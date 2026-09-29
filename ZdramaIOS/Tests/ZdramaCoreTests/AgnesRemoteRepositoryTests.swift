import XCTest
@testable import ZdramaCore

final class FakeAgnesHTTPClient: AgnesHTTPClient, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var queued: [(Data, Int)] = []

    func enqueueJSON(_ json: String, status: Int = 200) {
        queued.append((Data(json.utf8), status))
    }

    func enqueueJSONObject(_ object: Any, status: Int = 200) {
        queued.append((try! JSONSerialization.data(withJSONObject: object), status))
    }

    func enqueueData(_ data: Data, status: Int = 200) {
        queued.append((data, status))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !queued.isEmpty else {
            throw NSError(
                domain: "FakeAgnesHTTPClient",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No queued response"]
            )
        }
        let (data, status) = queued.removeFirst()
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

final class AgnesRemoteRepositoryTests: XCTestCase {
    func testGenerateScriptExtractsContentAndSendsChatCompletion() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "hello script"))
        let repo = AgnesTextRepository(client: fake)
        let settings = makeSettings()
        let project = makeProject()

        let script = try await repo.generateScript(
            settings: settings,
            project: project,
            storyPrompt: "episode-prompt"
        )

        XCTAssertEqual(script, "hello script")
        XCTAssertEqual(fake.requests.count, 1)
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/chat/completions"
        )
        assertAgnesHeaders(request, apiKey: "sk-test")
        let body = try requestJSON(request)
        XCTAssertEqual(body["model"] as? String, "agnes-text")
        XCTAssertEqual((body["temperature"] as? NSNumber)?.doubleValue, 0.7)
        XCTAssertEqual((body["max_tokens"] as? NSNumber)?.intValue, 4000)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, PromptDefaults.scriptCreatePrompt)
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(
            messages[1]["content"] as? String,
            """
            请根据以下项目信息创作一部短视频短剧剧本。

            项目标题：T
            故事提示词：episode-prompt
            风格：cinematic
            目标受众：all
            画幅比例：9:16
            镜头数量：6
            单镜头时长：5秒
            """
        )
    }

    func testGenerateScriptMissingTextModelDoesNotSend() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "should not be used"))
        let repo = AgnesTextRepository(client: fake)
        var settings = makeSettings()
        settings.textModel = "  "

        do {
            _ = try await repo.generateScript(
                settings: settings,
                project: makeProject(),
                storyPrompt: "p"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Text model is required")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGenerateScriptBlankApiKeyDoesNotSend() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "should not be used"))
        let repo = AgnesTextRepository(client: fake)
        var settings = makeSettings()
        settings.apiKey = ""

        do {
            _ = try await repo.generateScript(
                settings: settings,
                project: makeProject(),
                storyPrompt: "p"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Agnes API Key is required")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGenerateScriptEmptyContentThrows() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "  "))
        let repo = AgnesTextRepository(client: fake)

        do {
            _ = try await repo.generateScript(
                settings: makeSettings(),
                project: makeProject(),
                storyPrompt: "p"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Agnes 未返回脚本文本，请检查文本模型是否支持 chat/completions"
            )
        }
    }

    func testRewriteScriptExtractsContent() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "rewritten"))
        let repo = AgnesTextRepository(client: fake)

        let result = try await repo.rewriteScript(settings: makeSettings(), rawContent: "raw-content")

        XCTAssertEqual(result, "rewritten")
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual((body["temperature"] as? NSNumber)?.doubleValue, 0.7)
        XCTAssertEqual((body["max_tokens"] as? NSNumber)?.intValue, 6000)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, PromptDefaults.scriptRewritePrompt)
        XCTAssertEqual(
            messages[1]["content"] as? String,
            """
            请将以下内容改写为格式化短剧剧本。

            【原始内容】
            raw-content
            """
        )
    }

    func testPingSucceedsOnHTTP2xxWithoutExtractingContent() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueData(Data(), status: 201)
        let repo = AgnesTextRepository(client: fake)

        try await repo.ping(settings: makeSettings())

        XCTAssertEqual(fake.requests.count, 1)
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual((body["temperature"] as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual((body["max_tokens"] as? NSNumber)?.intValue, 8)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "ping")
    }

    func testGenerateStoryboardsParsesArrayAndMapsShots() async throws {
        let fake = FakeAgnesHTTPClient()
        let itemJSON = """
        [{"shot_number":"3","scene":"内景","action":"走进房间","dialogue":"你好","camera":"中景","image_prompt":"a room","video_prompt":"walk in","duration_seconds":"7","character_names":["Alice"]}]
        """
        fake.enqueueJSONObject(chatObject(content: "```json\n\(itemJSON)\n```"))
        let repo = AgnesStoryboardRepository(client: fake)
        let script = """
        ## S01 | 内景
        对白若干
        ## S02 | 外景
        动作若干
        """

        let shots = try await repo.generateStoryboards(
            settings: makeSettings(),
            project: makeProject(),
            script: script
        )

        XCTAssertEqual(shots.count, 1)
        let shot = try XCTUnwrap(shots.first)
        XCTAssertEqual(shot.id, 0)
        XCTAssertEqual(shot.projectId, 42)
        XCTAssertNil(shot.episodeId)
        XCTAssertEqual(shot.shotNumber, 3)
        XCTAssertEqual(shot.scene, "内景")
        XCTAssertEqual(shot.action, "走进房间")
        XCTAssertEqual(shot.dialogue, "你好")
        XCTAssertEqual(shot.camera, "中景")
        XCTAssertEqual(shot.imagePrompt, "a room")
        XCTAssertEqual(shot.videoPrompt, "walk in")
        XCTAssertEqual(shot.durationSeconds, 7)
        XCTAssertEqual(shot.characterNames, ["Alice"])
        XCTAssertEqual(shot.characterIds, "[\"Alice\"]")
        XCTAssertEqual(shot.imageStatus, .pending)
        XCTAssertEqual(shot.videoStatus, .pending)
        XCTAssertNil(shot.imageUrl)
        XCTAssertNil(shot.videoUrl)
        XCTAssertGreaterThan(shot.createdAt, 0)
        XCTAssertEqual(shot.createdAt, shot.updatedAt)

        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual((body["temperature"] as? NSNumber)?.doubleValue, 0.3)
        XCTAssertEqual((body["max_tokens"] as? NSNumber)?.intValue, 10000)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, PromptDefaults.storyboardPrompt)
        XCTAssertEqual(
            messages[1]["content"] as? String,
            """
            Project title: T
            Aspect ratio: 9:16
            Script contains 2 scene headers (## S01, ## S02 ...). Generate exactly one storyboard shot per scene, in order.
            Default shot duration seconds: 5

            Script:
            \(script)

            Return only a JSON array. Each item must use these keys: shot_number, scene, action, dialogue, camera, image_prompt, video_prompt, duration_seconds, character_names. character_names must be an array of character names that appear in this shot (use the exact character name strings from the script), or [] if no characters appear.
            """
        )
    }

    func testGenerateStoryboardsUsesExpectedShotCountWhenNoSceneHeaders() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: #"[{"shot_number":"1","scene":"s","action":"a","dialogue":"d","camera":"c","image_prompt":"i","video_prompt":"v","duration_seconds":"5","character_names":[]}]"#))
        let repo = AgnesStoryboardRepository(client: fake)

        let shots = try await repo.generateStoryboards(
            settings: makeSettings(),
            project: makeProject(),
            script: "plain script without headers"
        )

        XCTAssertEqual(shots[0].characterIds, nil)
        XCTAssertEqual(shots[0].characterNames, [])
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages[1]["content"] as? String)
        XCTAssertTrue(user.contains("Expected shot count: 6"))
        XCTAssertFalse(user.contains("Script contains"))
    }

    func testGenerateStoryboardsTruncatedThrows() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(chatObject(content: "", finishReason: "length"))
        let repo = AgnesStoryboardRepository(client: fake)

        do {
            _ = try await repo.generateStoryboards(
                settings: makeSettings(),
                project: makeProject(),
                script: "script"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "分镜生成被模型截断，请减少分镜数量或换用支持更长输出的文本模型"
            )
        }
    }

    func testGenerateImageReturnsURLAndOmitsReferenceImage() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["data": [["url": "https://cdn.example/a.png"]]])
        let repo = AgnesImageRepository(client: fake)

        let url = try await repo.generateImage(settings: makeSettings(), prompt: "a cat")

        XCTAssertEqual(url, "https://cdn.example/a.png")
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/images/generations"
        )
        assertAgnesHeaders(request, apiKey: "sk-test")
        let body = try requestJSON(request)
        XCTAssertEqual(body["model"] as? String, "agnes-image")
        XCTAssertEqual(body["prompt"] as? String, "a cat")
        XCTAssertEqual(body["size"] as? String, "1024x768")
        XCTAssertEqual((body["n"] as? NSNumber)?.intValue, 1)
        let extra = try XCTUnwrap(body["extra_body"] as? [String: Any])
        XCTAssertEqual(extra["response_format"] as? String, "url")
        XCTAssertNil(extra["image"])
        XCTAssertEqual(extra.count, 1)
    }

    func testGenerateImageFallsBackToTopLevelURL() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["url": "https://cdn.example/top.jpg"])
        let repo = AgnesImageRepository(client: fake)

        let url = try await repo.generateImage(settings: makeSettings(), prompt: "prompt")
        XCTAssertEqual(url, "https://cdn.example/top.jpg")
    }

    func testGenerateImageMissingModelDoesNotSend() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["url": "https://cdn.example/a.png"])
        let repo = AgnesImageRepository(client: fake)
        var settings = makeSettings()
        settings.imageModel = ""

        do {
            _ = try await repo.generateImage(settings: settings, prompt: "p")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Image model is required")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGenerateVideoPollsTwiceThenCompleted() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["status": "processing", "task_id": "t1"])
        fake.enqueueJSONObject(["status": "processing"])
        fake.enqueueJSONObject([
            "status": "completed",
            "metadata": ["url": "https://cdn.example/v.mp4"]
        ])
        var sleepCalls: [UInt64] = []
        let repo = AgnesVideoRepository(client: fake, sleep: { ns in
            sleepCalls.append(ns)
        })
        let shot = makeShot(
            videoPrompt: "vp",
            action: "act",
            camera: "cam",
            durationSeconds: 1,
            imageUrl: "https://cdn.example/ref.png"
        )

        let result = try await repo.generateVideo(
            settings: makeSettings(),
            shot: shot,
            imageReference: nil
        )

        XCTAssertEqual(result, VideoGenerationResult(taskId: "t1", videoUrl: "https://cdn.example/v.mp4"))
        XCTAssertEqual(fake.requests.count, 3)
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["POST", "GET", "GET"])
        XCTAssertEqual(
            fake.requests[0].url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/videos"
        )
        XCTAssertEqual(
            fake.requests[1].url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/videos/t1"
        )
        XCTAssertEqual(
            fake.requests[2].url?.absoluteString,
            "https://apihub.agnes-ai.com/v1/videos/t1"
        )
        assertAgnesHeaders(fake.requests[0], apiKey: "sk-test")
        assertAgnesHeaders(fake.requests[1], apiKey: "sk-test")
        XCTAssertEqual(sleepCalls, [10_000_000_000, 10_000_000_000])

        let body = try requestJSON(fake.requests[0])
        XCTAssertEqual(body["model"] as? String, "agnes-video")
        XCTAssertEqual(body["prompt"] as? String, "vp。act。cam。请使用中文对白与中文旁白。")
        XCTAssertEqual((body["num_frames"] as? NSNumber)?.intValue, 17)
        XCTAssertEqual((body["frame_rate"] as? NSNumber)?.intValue, 24)
        XCTAssertEqual((body["width"] as? NSNumber)?.intValue, 768)
        XCTAssertEqual((body["height"] as? NSNumber)?.intValue, 1152)
        XCTAssertEqual(body["image"] as? String, "https://cdn.example/ref.png")
        XCTAssertEqual(body["mode"] as? String, "ti2vid")
    }

    func testGenerateVideoCompletesImmediatelyWhenStatusCompletedWithURL() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject([
            "status": "completed",
            "id": "id-1",
            "video_url": "https://cdn.example/now.mp4"
        ])
        var sleepCalls: [UInt64] = []
        let repo = AgnesVideoRepository(client: fake, sleep: { ns in
            sleepCalls.append(ns)
        })

        let result = try await repo.generateVideo(
            settings: makeSettings(),
            shot: makeShot(imageUrl: "https://cdn.example/ref.png"),
            imageReference: "https://override.example/img.png"
        )

        XCTAssertEqual(result.taskId, "id-1")
        XCTAssertEqual(result.videoUrl, "https://cdn.example/now.mp4")
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertTrue(sleepCalls.isEmpty)
        let body = try requestJSON(try XCTUnwrap(fake.requests.first))
        XCTAssertEqual(body["image"] as? String, "https://override.example/img.png")
    }

    func testGenerateVideoTimesOutAfter60ProcessingPolls() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["status": "processing", "task_id": "t-timeout"])
        for _ in 0..<60 {
            fake.enqueueJSONObject(["status": "processing"])
        }
        var sleepCalls = 0
        let repo = AgnesVideoRepository(client: fake, sleep: { _ in
            sleepCalls += 1
        })

        do {
            _ = try await repo.generateVideo(
                settings: makeSettings(),
                shot: makeShot(imageUrl: "https://cdn.example/ref.png"),
                imageReference: nil
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Video generation timed out")
        }
        XCTAssertEqual(fake.requests.count, 61)
        XCTAssertEqual(sleepCalls, 60)
    }

    func testGenerateVideoMissingImageDoesNotSend() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["status": "completed"])
        let repo = AgnesVideoRepository(client: fake, sleep: { _ in })

        do {
            _ = try await repo.generateVideo(
                settings: makeSettings(),
                shot: makeShot(imageUrl: nil),
                imageReference: "  "
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Generate image before video")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGenerateVideoMissingModelDoesNotSend() async {
        let fake = FakeAgnesHTTPClient()
        let repo = AgnesVideoRepository(client: fake, sleep: { _ in })
        var settings = makeSettings()
        settings.videoModel = ""

        do {
            _ = try await repo.generateVideo(
                settings: settings,
                shot: makeShot(imageUrl: "https://cdn.example/ref.png"),
                imageReference: nil
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Video model is required")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGenerateVideoFailedUsesErrorMessage() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueJSONObject(["status": "processing", "task_id": "t-fail"])
        fake.enqueueJSONObject([
            "status": "failed",
            "error": ["message": "boom"]
        ])
        let repo = AgnesVideoRepository(client: fake, sleep: { _ in })

        do {
            _ = try await repo.generateVideo(
                settings: makeSettings(),
                shot: makeShot(imageUrl: "https://cdn.example/ref.png"),
                imageReference: nil
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "boom")
        }
    }

    func testDownloadShotImageWritesFileWithoutAuthorization() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueData(Data("png-bytes".utf8), status: 200)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgnesRemoteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = GeneratedMediaPaths(root: root)
        let repo = MediaDownloadRepository(client: fake, paths: paths)

        let saved = try await repo.downloadShotImage(
            projectId: 9,
            shotId: 4,
            url: "https://cdn.example/a.png"
        )

        XCTAssertEqual(saved, paths.shotImage(projectId: 9, shotId: 4, ext: "png").path)
        XCTAssertEqual(try String(contentsOfFile: saved, encoding: .utf8), "png-bytes")
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://cdn.example/a.png")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.timeoutInterval, 120)
    }

    func testDownloadNon2xxThrows() async {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueData(Data(), status: 403)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgnesRemoteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MediaDownloadRepository(
            client: fake,
            paths: GeneratedMediaPaths(root: root)
        )

        do {
            _ = try await repo.downloadShotVideo(
                projectId: 1,
                shotId: 2,
                url: "https://cdn.example/v.mp4"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Media download failed: HTTP 403")
        }
    }

    func testDeleteGeneratedMediaRemovesProjectDir() async throws {
        let fake = FakeAgnesHTTPClient()
        fake.enqueueData(Data("x".utf8), status: 200)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgnesRemoteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = GeneratedMediaPaths(root: root)
        let repo = MediaDownloadRepository(client: fake, paths: paths)
        _ = try await repo.downloadShotImage(
            projectId: 3,
            shotId: 1,
            url: "https://cdn.example/a.jpg"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.projectDir(3).path))

        try repo.deleteGeneratedMedia(projectId: 3)

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.projectDir(3).path))
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

    private func makeProject() -> DramaProject {
        DramaProject(
            id: 42,
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

    private func makeShot(
        videoPrompt: String = "vp",
        action: String = "act",
        camera: String = "cam",
        durationSeconds: Int = 1,
        imageUrl: String?
    ) -> StoryboardShot {
        StoryboardShot(
            id: 8,
            projectId: 42,
            episodeId: nil,
            shotNumber: 1,
            scene: "scene",
            action: action,
            dialogue: "hi",
            camera: camera,
            imagePrompt: "img",
            videoPrompt: videoPrompt,
            durationSeconds: durationSeconds,
            characterNames: [],
            characterIds: nil,
            imageStatus: .completed,
            imageUrl: imageUrl,
            imageLocalPath: nil,
            imageErrorMessage: nil,
            videoStatus: .pending,
            videoTaskId: nil,
            videoUrl: nil,
            videoLocalPath: nil,
            videoErrorMessage: nil,
            createdAt: 1,
            updatedAt: 1
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

    private func assertAgnesHeaders(_ request: URLRequest, apiKey: String) {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(apiKey)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
