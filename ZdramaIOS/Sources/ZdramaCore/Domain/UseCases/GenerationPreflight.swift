import Foundation

public struct PreflightInput {
    public var apiKey: String
    public var episodeContent: String?
    public var scriptContent: String?
    public var shots: [StoryboardShot]
    public var fileExists: (String) -> Bool

    public init(
        apiKey: String,
        episodeContent: String?,
        scriptContent: String?,
        shots: [StoryboardShot],
        fileExists: @escaping (String) -> Bool
    ) {
        self.apiKey = apiKey
        self.episodeContent = episodeContent
        self.scriptContent = scriptContent
        self.shots = shots
        self.fileExists = fileExists
    }
}

public enum PreflightError: LocalizedError, Equatable {
    case missingApiKey
    case missingRawContent
    case missingScript
    case missingStoryboards
    case missingImages
    case missingLocalVideos

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Agnes API Key is required"
        case .missingRawContent, .missingScript:
            return "请先为本集创作或改写脚本"
        case .missingStoryboards:
            return "请先生成分镜"
        case .missingImages:
            return "请先生成分镜图"
        case .missingLocalVideos:
            return "请先生成并下载全部分镜视频后再合成成片"
        }
    }
}

public enum GenerationPreflight {
    public static func check(stage: String, input: PreflightInput) throws {
        if stage != "final_video" && isBlank(input.apiKey) {
            throw PreflightError.missingApiKey
        }

        switch stage {
        case "rewrite":
            if isBlank(input.episodeContent) {
                throw PreflightError.missingRawContent
            }
        case "storyboard":
            if isBlank(input.scriptContent) {
                throw PreflightError.missingScript
            }
        case "image", "video", "final_video":
            if input.shots.isEmpty {
                throw PreflightError.missingStoryboards
            }
            if stage == "video" && input.shots.contains(where: { !hasImage($0, fileExists: input.fileExists) }) {
                throw PreflightError.missingImages
            }
            if stage == "final_video" && input.shots.contains(where: { !hasLocalVideo($0, fileExists: input.fileExists) }) {
                throw PreflightError.missingLocalVideos
            }
        default:
            break
        }
    }

    private static func hasImage(_ shot: StoryboardShot, fileExists: (String) -> Bool) -> Bool {
        if let path = shot.imageLocalPath, fileExists(path) {
            return true
        }
        return !isBlank(shot.imageUrl)
    }

    private static func hasLocalVideo(_ shot: StoryboardShot, fileExists: (String) -> Bool) -> Bool {
        guard let path = shot.videoLocalPath else { return false }
        return fileExists(path)
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
