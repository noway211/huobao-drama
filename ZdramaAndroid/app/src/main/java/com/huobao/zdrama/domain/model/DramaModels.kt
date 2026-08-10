package com.huobao.zdrama.domain.model

enum class ProjectStatus {
    DRAFT,
    PROCESSING,
    COMPLETED,
    FAILED,
    CANCELLED
}

enum class GenerationStage {
    NONE,
    TEXT,
    STORYBOARD,
    IMAGE,
    VIDEO,
    FINAL_VIDEO
}

enum class AssetStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    FAILED
}

data class CreateDramaInput(
    val title: String,
    val prompt: String,
    val style: String,
    val targetAudience: String,
    val aspectRatio: String,
    val shotCount: Int,
    val shotDurationSeconds: Int
)

data class DramaProject(
    val id: Long,
    val title: String,
    val prompt: String,
    val style: String,
    val targetAudience: String,
    val aspectRatio: String,
    val shotCount: Int,
    val shotDurationSeconds: Int,
    val status: ProjectStatus,
    val currentStage: GenerationStage,
    val errorMessage: String?,
    val generatedScript: String?,
    val finalVideoStatus: AssetStatus,
    val finalVideoLocalPath: String?,
    val finalVideoErrorMessage: String?,
    val createdAt: Long,
    val updatedAt: Long
)

enum class EpisodeStatus {
    DRAFT,
    REWRITING,
    COMPLETED,
    FAILED
}

data class Episode(
    val id: Long,
    val projectId: Long,
    val episodeNumber: Int,
    val title: String,
    val content: String?,
    val scriptContent: String?,
    val status: EpisodeStatus,
    val createdAt: Long,
    val updatedAt: Long
)

data class StoryboardShot(
    val id: Long,
    val projectId: Long,
    val shotNumber: Int,
    val scene: String,
    val action: String,
    val dialogue: String,
    val camera: String,
    val imagePrompt: String,
    val videoPrompt: String,
    val durationSeconds: Int,
    val imageStatus: AssetStatus,
    val imageUrl: String?,
    val imageLocalPath: String?,
    val imageErrorMessage: String?,
    val videoStatus: AssetStatus,
    val videoTaskId: String?,
    val videoUrl: String?,
    val videoLocalPath: String?,
    val videoErrorMessage: String?,
    val createdAt: Long,
    val updatedAt: Long
)

data class Character(
    val id: Long,
    val projectId: Long,
    val episodeId: Long?,
    val name: String,
    val role: String,
    val description: String,
    val appearance: String,
    val personality: String,
    val imageStatus: AssetStatus,
    val imageUrl: String?,
    val imageLocalPath: String?,
    val imageErrorMessage: String?,
    val createdAt: Long,
    val updatedAt: Long
)
