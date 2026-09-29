import Foundation

public struct ParsedStoryboardItem: Equatable, Sendable, Decodable {
    public var shotNumber: String?
    public var scene: String
    public var action: String
    public var dialogue: String
    public var camera: String
    public var imagePrompt: String
    public var videoPrompt: String
    public var durationSeconds: String?
    public var characterNames: [String]?

    enum CodingKeys: String, CodingKey {
        case shotNumber = "shot_number"
        case scene
        case action
        case dialogue
        case camera
        case imagePrompt = "image_prompt"
        case videoPrompt = "video_prompt"
        case durationSeconds = "duration_seconds"
        case characterNames = "character_names"
    }

    public init(
        shotNumber: String? = nil,
        scene: String = "",
        action: String = "",
        dialogue: String = "",
        camera: String = "",
        imagePrompt: String = "",
        videoPrompt: String = "",
        durationSeconds: String? = nil,
        characterNames: [String]? = nil
    ) {
        self.shotNumber = shotNumber
        self.scene = scene
        self.action = action
        self.dialogue = dialogue
        self.camera = camera
        self.imagePrompt = imagePrompt
        self.videoPrompt = videoPrompt
        self.durationSeconds = durationSeconds
        self.characterNames = characterNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shotNumber = try container.decodeIfPresent(String.self, forKey: .shotNumber)
        scene = try container.decodeIfPresent(String.self, forKey: .scene) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        dialogue = try container.decodeIfPresent(String.self, forKey: .dialogue) ?? ""
        camera = try container.decodeIfPresent(String.self, forKey: .camera) ?? ""
        imagePrompt = try container.decodeIfPresent(String.self, forKey: .imagePrompt) ?? ""
        videoPrompt = try container.decodeIfPresent(String.self, forKey: .videoPrompt) ?? ""
        durationSeconds = try container.decodeIfPresent(String.self, forKey: .durationSeconds)
        characterNames = try container.decodeIfPresent([String].self, forKey: .characterNames)
    }
}

public enum StoryboardJSONParserError: LocalizedError {
    case notJSON

    public var errorDescription: String? {
        "Agnes storyboard response is not JSON"
    }
}

public enum StoryboardJSONParser {
    private static let sceneHeaderRegex = try! NSRegularExpression(
        pattern: #"^##\s*S\d+\b"#,
        options: .anchorsMatchLines
    )

    public static func parse(_ content: String) throws -> [ParsedStoryboardItem] {
        let json = try extractJSONArray(content)
        return try JSONDecoder().decode([ParsedStoryboardItem].self, from: Data(json.utf8))
    }

    public static func countSceneHeaders(_ script: String) -> Int {
        let range = NSRange(script.startIndex..., in: script)
        return sceneHeaderRegex.numberOfMatches(in: script, options: [], range: range)
    }

    private static func extractJSONArray(_ content: String) throws -> String {
        guard let start = content.firstIndex(of: "["),
              let end = content.lastIndex(of: "]"),
              start < end
        else {
            throw StoryboardJSONParserError.notJSON
        }
        return String(content[start...end])
    }
}
