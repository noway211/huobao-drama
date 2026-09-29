import Foundation

public struct AgnesImageRepository: Sendable {
    private let client: AgnesHTTPClient

    public init(client: AgnesHTTPClient) {
        self.client = client
    }

    public func generateImage(settings: AgnesSettings, prompt: String) async throws -> String {
        try AgnesRequest.requireImageModel(settings)
        let body: [String: Any] = [
            "model": settings.imageModel,
            "prompt": prompt,
            "size": "1024x768",
            "n": 1,
            "extra_body": [
                "response_format": "url"
            ]
        ]
        let request = try AgnesRequest.jsonPOST(
            url: AgnesEndpoints.imagesGenerations(baseURL: settings.baseUrl),
            apiKey: settings.apiKey,
            body: body
        )
        let json = try await AgnesRequest.sendJSON(client: client, request: request)
        guard let url = extractImageURL(json), !AgnesRequest.isBlank(url) else {
            throw AgnesClientError.noImageURL
        }
        return url
    }

    private func extractImageURL(_ json: Any) -> String? {
        guard let object = AgnesRequest.object(json) else { return nil }
        if let data = object["data"] as? [Any],
           let first = data.first as? [String: Any],
           let url = AgnesRequest.string(first["url"]),
           !AgnesRequest.isBlank(url) {
            return url
        }
        return AgnesRequest.string(object["url"])
    }
}
