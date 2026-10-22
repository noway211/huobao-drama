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

    public func characterImage(projectId: Int64, characterId: Int64, ext: String) -> URL {
        projectDir(projectId).appendingPathComponent("char_\(characterId)_image.\(ext)")
    }

    public func shotVideo(projectId: Int64, shotId: Int64, ext: String) -> URL {
        projectDir(projectId).appendingPathComponent("shot_\(shotId)_video.\(ext)")
    }

    public func finalVideo(projectId: Int64, episodeId: Int64) -> URL {
        projectDir(projectId)
            .appendingPathComponent("episode_\(episodeId)", isDirectory: true)
            .appendingPathComponent("final_video.mp4")
    }

    /// 存库用的路径：位于 root 之下时返回相对路径，否则原样返回。
    public func relativePath(of file: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return file.path }
        return String(filePath.dropFirst(prefix.count))
    }

    /// 把存库的路径还原成当前沙盒里的绝对路径。
    /// 绝对路径指向的文件还在就直接用；不在则按 `generated/` 之后的部分回落到当前 root。
    public func resolve(_ stored: String) -> URL {
        if stored.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: stored) {
                return URL(fileURLWithPath: stored)
            }
            if let range = stored.range(of: "/generated/") {
                let tail = String(stored[range.upperBound...])
                let candidate = root.appendingPathComponent("generated").appendingPathComponent(tail)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            return URL(fileURLWithPath: stored)
        }
        return root.appendingPathComponent(stored)
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
