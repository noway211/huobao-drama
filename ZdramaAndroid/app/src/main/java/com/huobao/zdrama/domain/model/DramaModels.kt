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
    val characterNames: List<String>,
    /**
     * 角色绑定（与 Harmony 端语义一致）：JSON 字符串，兼容两种格式——
     * 分镜生成时写入 LLM 返回的角色名字符串数组（如 ["Alice","Bob"]）；
     * 用户手工绑定后写入角色数字 ID 数组（如 [1,3]）。null/空串视为无绑定。
     */
    val characterIds: String? = null,
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
