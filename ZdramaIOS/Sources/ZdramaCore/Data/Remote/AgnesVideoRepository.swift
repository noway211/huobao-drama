import Foundation

public struct VideoGenerationResult: Equatable, Sendable {
    public var taskId: String?
    public var videoUrl: String

    public init(taskId: String?, videoUrl: String) {
        self.taskId = taskId
        self.videoUrl = videoUrl
    }
}

public struct AgnesVideoRepository: @unchecked Sendable {
    private static let pollIntervalNanoseconds: UInt64 = 10_000_000_000
    private static let maxPollCount = 60
    private static let minSeconds = 4
    private static let maxSeconds = 12

    private let client: AgnesHTTPClient
    private let sleep: (UInt64) async -> Void

    public init(
        client: AgnesHTTPClient,
        sleep: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) {
        self.client = client
        self.sleep = sleep
    }

    public func generateVideo(
        settings: AgnesSettings,
        shot: StoryboardShot,
        imageReference: String?
    ) async throws -> VideoGenerationResult {
        try AgnesRequest.requireVideoModel(settings)
        let imageURL = firstNonBlank(imageReference, shot.imageUrl)
        guard let imageURL else {
            throw AgnesClientError.generateImageBeforeVideo
        }

        let body: [String: Any] = [
            "model": settings.videoModel,
            "prompt": buildPrompt(shot),
            "seconds": videoSeconds(shot.durationSeconds),
            "mode": "keyframe",
            "size": "720P",
            "aspect_ratio": "16:9",
            "first_frame": imageURL
        ]
        let request = try AgnesRequest.jsonPOST(
            url: AgnesEndpoints.videos(baseURL: settings.baseUrl),
            apiKey: settings.apiKey,
            body: body
        )
        let json = try await AgnesRequest.sendJSON(client: client, request: request)
        let object = AgnesRequest.object(json) ?? [:]
        let status = AgnesRequest.string(object["status"])
        let immediateURL = extractVideoURL(object)
        if status == "completed", let immediateURL, !AgnesRequest.isBlank(immediateURL) {
            let taskId = AgnesRequest.string(object["video_id"])
                ?? AgnesRequest.string(object["task_id"])
                ?? AgnesRequest.string(object["id"])
            return VideoGenerationResult(taskId: taskId, videoUrl: immediateURL)
        }
        guard let videoId = AgnesRequest.string(object["video_id"])
            ?? AgnesRequest.string(object["task_id"])
            ?? AgnesRequest.string(object["id"]) else {
            throw AgnesClientError.noVideoTaskId
        }
        return try await pollVideo(settings: settings, videoId: videoId)
    }

    private func pollVideo(settings: AgnesSettings, videoId: String) async throws -> VideoGenerationResult {
        for _ in 0..<Self.maxPollCount {
            await sleep(Self.pollIntervalNanoseconds)
            let request = AgnesRequest.jsonGET(
                url: AgnesEndpoints.video(
                    baseURL: settings.baseUrl,
                    videoId: videoId,
                    modelName: settings.videoModel
                ),
                apiKey: settings.apiKey
            )
            let json = try await AgnesRequest.sendJSON(client: client, request: request)
            let object = AgnesRequest.object(json) ?? [:]
            switch AgnesRequest.string(object["status"]) {
            case "completed":
                guard let videoURL = extractVideoURL(object), !AgnesRequest.isBlank(videoURL) else {
                    throw AgnesClientError.videoCompletedWithoutURL
                }
                return VideoGenerationResult(taskId: videoId, videoUrl: videoURL)
            case "failed":
                throw AgnesClientError.videoFailed(parseError(object["error"]))
            default:
                break
            }
        }
        throw AgnesClientError.videoTimedOut
    }

    /// 2.5 的 seconds 是字符串，合法范围 4–12。镜头时长夹到这个区间。
    private func videoSeconds(_ durationSeconds: Int) -> String {
        let clamped = min(max(durationSeconds, Self.minSeconds), Self.maxSeconds)
        return String(clamped)
    }

    private func buildPrompt(_ shot: StoryboardShot) -> String {
        let parts = [shot.videoPrompt, shot.action, shot.camera].compactMap { value -> String? in
            AgnesRequest.isBlank(value) ? nil : value
        }
        return parts.joined(separator: "。") + "。请使用中文对白与中文旁白。"
    }

    private func extractVideoURL(_ object: [String: Any]) -> String? {
        if let metadata = object["metadata"] as? [String: Any],
           let url = AgnesRequest.string(metadata["url"]),
           !AgnesRequest.isBlank(url) {
            return url
        }
        for key in ["video_url", "url", "remixed_from_video_id"] {
            if let url = AgnesRequest.string(object[key]), !AgnesRequest.isBlank(url) {
                return url
            }
        }
        return nil
    }

    private func parseError(_ error: Any?) -> String {
        guard let error, !(error is NSNull) else {
            return "Video generation failed"
        }
        if let message = error as? String, !AgnesRequest.isBlank(message) {
            return message
        }
        if let object = error as? [String: Any],
           let message = AgnesRequest.string(object["message"]),
           !AgnesRequest.isBlank(message) {
            return message
        }
        return "Video generation failed"
    }

    private func firstNonBlank(_ values: String?...) -> String? {
        for value in values {
            if let value, !AgnesRequest.isBlank(value) {
                return value
            }
        }
        return nil
    }
}
