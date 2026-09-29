import Foundation

public struct MediaDownloadRepository: Sendable {
    private let client: AgnesHTTPClient
    private let paths: GeneratedMediaPaths

    public init(client: AgnesHTTPClient, paths: GeneratedMediaPaths) {
        self.client = client
        self.paths = paths
    }

    public func downloadShotImage(projectId: Int64, shotId: Int64, url: String) async throws -> String {
        try await download(projectId: projectId, shotId: shotId, url: url, kind: .image)
    }

    public func downloadShotVideo(projectId: Int64, shotId: Int64, url: String) async throws -> String {
        try await download(projectId: projectId, shotId: shotId, url: url, kind: .video)
    }

    public func deleteGeneratedMedia(projectId: Int64) throws {
        let dir = paths.projectDir(projectId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func download(
        projectId: Int64,
        shotId: Int64,
        url: String,
        kind: MediaKind
    ) async throws -> String {
        guard let downloadURL = URL(string: url) else {
            throw AgnesClientError.invalidResponse
        }
        var request = URLRequest(url: downloadURL, timeoutInterval: 120)
        request.httpMethod = "GET"
        let (data, response) = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AgnesClientError.mediaDownloadFailed(response.statusCode)
        }
        let ext = MediaPathHelpers.extensionFromURL(url, kind: kind)
        let dest: URL
        switch kind {
        case .image:
            dest = paths.shotImage(projectId: projectId, shotId: shotId, ext: ext)
        case .video:
            dest = paths.shotVideo(projectId: projectId, shotId: shotId, ext: ext)
        }
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: dest, options: .atomic)
        return dest.path
    }
}
