public struct AgnesSettings: Equatable, Sendable {
    public var apiKey: String
    public var baseUrl: String
    public var textModel: String
    public var imageModel: String
    public var videoModel: String
    public var requestTimeoutSeconds: Int
    public var customScriptCreatePrompt: String?
    public var customScriptRewritePrompt: String?
    public var customCharacterExtractPrompt: String?
    public var customStoryboardPrompt: String?

    public static let defaultBaseURL = "https://apihub.agnes-ai.com/"
    public static let defaultImageModel = "agnes-image-2.0-flash"
    public static let defaultVideoModel = "agnes-video-v2.0"
    public static let defaultTimeoutSeconds = 120

    public init(
        apiKey: String,
        baseUrl: String,
        textModel: String,
        imageModel: String,
        videoModel: String,
        requestTimeoutSeconds: Int,
        customScriptCreatePrompt: String? = nil,
        customScriptRewritePrompt: String? = nil,
        customCharacterExtractPrompt: String? = nil,
        customStoryboardPrompt: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.textModel = textModel
        self.imageModel = imageModel
        self.videoModel = videoModel
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.customScriptCreatePrompt = customScriptCreatePrompt
        self.customScriptRewritePrompt = customScriptRewritePrompt
        self.customCharacterExtractPrompt = customCharacterExtractPrompt
        self.customStoryboardPrompt = customStoryboardPrompt
    }

    public static func defaults() -> AgnesSettings {
        AgnesSettings(
            apiKey: "",
            baseUrl: defaultBaseURL,
            textModel: "",
            imageModel: defaultImageModel,
            videoModel: defaultVideoModel,
            requestTimeoutSeconds: defaultTimeoutSeconds
        )
    }
}
