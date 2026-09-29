import Foundation

public struct GeneratedMediaPaths: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func projectDir(_ projectId: Int64) -> URL {
        root
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("\(projectId)", isDirectory: true)
    }

    public func shotImage(projectId: Int64, shotId: Int64, ext: String) -> URL {
        projectDir(projectId).appendingPathComponent("shot_\(shotId)_image.\(ext)")
    }

    public func shotVideo(projectId: Int64, shotId: Int64, ext: String) -> URL {
        projectDir(projectId).appendingPathComponent("shot_\(shotId)_video.\(ext)")
    }

    public func finalVideo(projectId: Int64, episodeId: Int64) -> URL {
        projectDir(projectId)
            .appendingPathComponent("episode_\(episodeId)", isDirectory: true)
            .appendingPathComponent("final_video.mp4")
    }
}

public enum MediaKind {
    case image
    case video
}

public enum MediaPathHelpers {
    public static func extensionFromURL(_ url: String, kind: MediaKind) -> String {
        let path = URL(string: url)?.path ?? url
        let ext = URL(fileURLWithPath: path).pathExtension
        if isValidExtension(ext) {
            return ext
        }
        return kind == .image ? "jpg" : "mp4"
    }

    private static func isValidExtension(_ ext: String) -> Bool {
        guard (2...5).contains(ext.count) else { return false }
        return ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
