import Foundation

public protocol AgnesHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAgnesHTTPClient: AgnesHTTPClient {
    private let session: URLSession

    public init(timeoutSeconds: Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(timeoutSeconds)
        configuration.timeoutIntervalForResource = TimeInterval(timeoutSeconds)
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgnesClientError.invalidResponse
        }
        return (data, http)
    }
}

public enum AgnesClientError: LocalizedError, Equatable {
    case apiKeyRequired
    case textModelRequired
    case imageModelRequired
    case videoModelRequired
    case emptyScript
    case emptyRewrite
    case truncatedStoryboard
    case emptyStoryboard
    case noImageURL
    case generateImageBeforeVideo
    case noVideoTaskId
    case videoCompletedWithoutURL
    case videoFailed(String)
    case videoTimedOut
    case mediaDownloadFailed(Int)
    case httpFailed(Int)
    case invalidResponse
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .apiKeyRequired:
            return "Agnes API Key is required"
        case .textModelRequired:
            return "Text model is required"
        case .imageModelRequired:
            return "Image model is required"
        case .videoModelRequired:
            return "Video model is required"
        case .emptyScript:
            return "Agnes 未返回脚本文本，请检查文本模型是否支持 chat/completions"
        case .emptyRewrite:
            return "Agnes 未返回改写内容，请检查文本模型是否支持 chat/completions"
        case .truncatedStoryboard:
            return "分镜生成被模型截断，请减少分镜数量或换用支持更长输出的文本模型"
        case .emptyStoryboard:
            return "Agnes 未返回分镜内容"
        case .noImageURL:
            return "No image URL in Agnes response"
        case .generateImageBeforeVideo:
            return "Generate image before video"
        case .noVideoTaskId:
            return "No task_id/id in Agnes video response"
        case .videoCompletedWithoutURL:
            return "Agnes video completed without URL"
        case .videoFailed(let message):
            return message
        case .videoTimedOut:
            return "Video generation timed out"
        case .mediaDownloadFailed(let code):
            return "Media download failed: HTTP \(code)"
        case .httpFailed(let code):
            return "Agnes request failed: HTTP \(code)"
        case .invalidResponse:
            return "Agnes request failed: invalid response"
        case .invalidJSON:
            return "Agnes request failed: invalid JSON"
        }
    }
}

enum AgnesRequest {
    static func requireAPIKey(_ settings: AgnesSettings) throws {
        if isBlank(settings.apiKey) {
            throw AgnesClientError.apiKeyRequired
        }
    }

    static func requireTextModel(_ settings: AgnesSettings) throws {
        try requireAPIKey(settings)
        if isBlank(settings.textModel) {
            throw AgnesClientError.textModelRequired
        }
    }

    static func requireImageModel(_ settings: AgnesSettings) throws {
        try requireAPIKey(settings)
        if isBlank(settings.imageModel) {
            throw AgnesClientError.imageModelRequired
        }
    }

    static func requireVideoModel(_ settings: AgnesSettings) throws {
        try requireAPIKey(settings)
        if isBlank(settings.videoModel) {
            throw AgnesClientError.videoModelRequired
        }
    }

    static func jsonPOST(url: URL, apiKey: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func jsonGET(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func sendJSON(
        client: AgnesHTTPClient,
        request: URLRequest
    ) async throws -> Any {
        let (data, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AgnesClientError.httpFailed(response.statusCode)
        }
        guard !data.isEmpty else {
            throw AgnesClientError.invalidJSON
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func sendExpecting2xx(client: AgnesHTTPClient, request: URLRequest) async throws {
        let (_, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AgnesClientError.httpFailed(response.statusCode)
        }
    }

    static func chatBody(
        model: String,
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int
    ) -> [String: Any] {
        [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
    }

    static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    static func object(_ json: Any) -> [String: Any]? {
        json as? [String: Any]
    }

    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return value as? String
    }
}
