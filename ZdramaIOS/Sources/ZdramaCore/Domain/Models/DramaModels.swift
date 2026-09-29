public enum ProjectStatus: String, Equatable, Sendable {
    case draft = "DRAFT"
    case processing = "PROCESSING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    public init(persisted: String?) {
        self = Self(rawValue: persisted ?? "") ?? .draft
    }
}

public enum GenerationStage: String, Equatable, Sendable {
    case none = "NONE"
    case text = "TEXT"
    case storyboard = "STORYBOARD"
    case image = "IMAGE"
    case video = "VIDEO"
    case finalVideo = "FINAL_VIDEO"

    public init(persisted: String?) {
        self = Self(rawValue: persisted ?? "") ?? .none
    }
}

public enum AssetStatus: String, Equatable, Sendable {
    case pending = "PENDING"
    case processing = "PROCESSING"
    case completed = "COMPLETED"
    case failed = "FAILED"

    public init(persisted: String?) {
        self = Self(rawValue: persisted ?? "") ?? .pending
    }
}

public enum EpisodeStatus: String, Equatable, Sendable {
    case draft = "DRAFT"
    case rewriting = "REWRITING"
    case completed = "COMPLETED"
    case failed = "FAILED"

    public init(persisted: String?) {
        self = Self(rawValue: persisted ?? "") ?? .draft
    }
}

public struct CreateDramaInput: Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var style: String
    public var targetAudience: String
    public var aspectRatio: String
    public var shotCount: Int
    public var shotDurationSeconds: Int

    public init(
        title: String,
        prompt: String,
        style: String,
        targetAudience: String,
        aspectRatio: String,
        shotCount: Int,
        shotDurationSeconds: Int
    ) {
        self.title = title
        self.prompt = prompt
        self.style = style
        self.targetAudience = targetAudience
        self.aspectRatio = aspectRatio
        self.shotCount = shotCount
        self.shotDurationSeconds = shotDurationSeconds
    }
}

public struct DramaProject: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var prompt: String
    public var style: String
    public var targetAudience: String
    public var aspectRatio: String
    public var shotCount: Int
    public var shotDurationSeconds: Int
    public var status: ProjectStatus
    public var currentStage: GenerationStage
    public var errorMessage: String?
    public var generatedScript: String?
    public var finalVideoStatus: AssetStatus
    public var finalVideoLocalPath: String?
    public var finalVideoErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: Int64,
        title: String,
        prompt: String,
        style: String,
        targetAudience: String,
        aspectRatio: String,
        shotCount: Int,
        shotDurationSeconds: Int,
        status: ProjectStatus,
        currentStage: GenerationStage,
        errorMessage: String?,
        generatedScript: String?,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.style = style
        self.targetAudience = targetAudience
        self.aspectRatio = aspectRatio
        self.shotCount = shotCount
        self.shotDurationSeconds = shotDurationSeconds
        self.status = status
        self.currentStage = currentStage
        self.errorMessage = errorMessage
        self.generatedScript = generatedScript
        self.finalVideoStatus = finalVideoStatus
        self.finalVideoLocalPath = finalVideoLocalPath
        self.finalVideoErrorMessage = finalVideoErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Episode: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var projectId: Int64
    public var episodeNumber: Int
    public var title: String
    public var content: String?
    public var scriptContent: String?
    public var status: EpisodeStatus
    public var finalVideoStatus: AssetStatus
    public var finalVideoLocalPath: String?
    public var finalVideoErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: Int64,
        projectId: Int64,
        episodeNumber: Int,
        title: String,
        content: String?,
        scriptContent: String?,
        status: EpisodeStatus,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.projectId = projectId
        self.episodeNumber = episodeNumber
        self.title = title
        self.content = content
        self.scriptContent = scriptContent
        self.status = status
        self.finalVideoStatus = finalVideoStatus
        self.finalVideoLocalPath = finalVideoLocalPath
        self.finalVideoErrorMessage = finalVideoErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StoryboardShot: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var projectId: Int64
    public var episodeId: Int64?
    public var shotNumber: Int
    public var scene: String
    public var action: String
    public var dialogue: String
    public var camera: String
    public var imagePrompt: String
    public var videoPrompt: String
    public var durationSeconds: Int
    public var characterNames: [String]
    public var characterIds: String?
    public var imageStatus: AssetStatus
    public var imageUrl: String?
    public var imageLocalPath: String?
    public var imageErrorMessage: String?
    public var videoStatus: AssetStatus
    public var videoTaskId: String?
    public var videoUrl: String?
    public var videoLocalPath: String?
    public var videoErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: Int64,
        projectId: Int64,
        episodeId: Int64?,
        shotNumber: Int,
        scene: String,
        action: String,
        dialogue: String,
        camera: String,
        imagePrompt: String,
        videoPrompt: String,
        durationSeconds: Int,
        characterNames: [String],
        characterIds: String?,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?,
        videoStatus: AssetStatus,
        videoTaskId: String?,
        videoUrl: String?,
        videoLocalPath: String?,
        videoErrorMessage: String?,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.projectId = projectId
        self.episodeId = episodeId
        self.shotNumber = shotNumber
        self.scene = scene
        self.action = action
        self.dialogue = dialogue
        self.camera = camera
        self.imagePrompt = imagePrompt
        self.videoPrompt = videoPrompt
        self.durationSeconds = durationSeconds
        self.characterNames = characterNames
        self.characterIds = characterIds
        self.imageStatus = imageStatus
        self.imageUrl = imageUrl
        self.imageLocalPath = imageLocalPath
        self.imageErrorMessage = imageErrorMessage
        self.videoStatus = videoStatus
        self.videoTaskId = videoTaskId
        self.videoUrl = videoUrl
        self.videoLocalPath = videoLocalPath
        self.videoErrorMessage = videoErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Character: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var projectId: Int64
    public var episodeId: Int64?
    public var name: String
    public var role: String
    public var description: String
    public var appearance: String
    public var personality: String
    public var imageStatus: AssetStatus
    public var imageUrl: String?
    public var imageLocalPath: String?
    public var imageErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: Int64,
        projectId: Int64,
        episodeId: Int64?,
        name: String,
        role: String,
        description: String,
        appearance: String,
        personality: String,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.projectId = projectId
        self.episodeId = episodeId
        self.name = name
        self.role = role
        self.description = description
        self.appearance = appearance
        self.personality = personality
        self.imageStatus = imageStatus
        self.imageUrl = imageUrl
        self.imageLocalPath = imageLocalPath
        self.imageErrorMessage = imageErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
