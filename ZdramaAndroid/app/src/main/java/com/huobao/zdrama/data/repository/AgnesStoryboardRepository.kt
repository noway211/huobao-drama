package com.huobao.zdrama.data.repository

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken
import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.ChatCompletionRequest
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.remote.ChatResponseTextExtractor
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.StoryboardShot

class AgnesStoryboardRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory(),
    private val gson: Gson = Gson()
) {
    suspend fun generateStoryboards(settings: AgnesSettings, project: DramaProject, script: String? = null): Result<List<StoryboardShot>> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.textModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Text model is required"))
        }
        val scriptToUse = script ?: project.generatedScript.orEmpty()
        if (scriptToUse.isBlank()) {
            return Result.failure(IllegalArgumentException("Generate script before storyboard"))
        }

        return runCatching {
            val service = clientFactory.create(settings)
            val response = service.createChatCompletion(
                ChatCompletionRequest(
                    model = settings.textModel,
                    messages = listOf(
                        ChatMessage(role = "system", content = SYSTEM_PROMPT),
                        ChatMessage(role = "user", content = buildUserPrompt(project, scriptToUse))
                    ),
                    temperature = 0.3,
                    max_tokens = 6000
                )
            )
            Log.d(TAG, "storyboard response structure: ${ChatResponseTextExtractor.describe(response)}")
            val content = ChatResponseTextExtractor.extractFinalContent(response)
            if (content.isBlank() && ChatResponseTextExtractor.finishReason(response) == "length") {
                throw IllegalStateException("分镜生成被模型截断，请减少分镜数量或换用支持更长输出的文本模型")
            }
            val items = parseStoryboardJson(content)
            if (items.isEmpty()) {
                throw IllegalStateException("Agnes 未返回分镜内容")
            }
            val now = System.currentTimeMillis()
            items.mapIndexed { index, item ->
                StoryboardShot(
                    id = 0L,
                    projectId = project.id,
                    shotNumber = item.shotNumber?.toIntOrNull() ?: (index + 1),
                    scene = item.scene.orEmpty(),
                    action = item.action.orEmpty(),
                    dialogue = item.dialogue.orEmpty(),
                    camera = item.camera.orEmpty(),
                    imagePrompt = item.imagePrompt.orEmpty(),
                    videoPrompt = item.videoPrompt.orEmpty(),
                    durationSeconds = item.durationSeconds?.toIntOrNull() ?: project.shotDurationSeconds,
                    imageStatus = AssetStatus.PENDING,
                    imageUrl = null,
                    imageLocalPath = null,
                    imageErrorMessage = null,
                    videoStatus = AssetStatus.PENDING,
                    videoTaskId = null,
                    videoUrl = null,
                    videoLocalPath = null,
                    videoErrorMessage = null,
                    createdAt = now,
                    updatedAt = now
                )
            }
        }
    }

    private fun parseStoryboardJson(content: String): List<StoryboardItem> {
        val json = extractJsonArray(content)
        Log.d(TAG, "Extracted JSON length: ${json.length}, content preview: ${json.take(200)}...")
        val type = object : TypeToken<List<StoryboardItem>>() {}.type
        return try {
            gson.fromJson(json, type)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse storyboard JSON. Full content:\n$content", e)
            throw e
        }
    }

    private fun extractJsonArray(content: String): String {
        // Try parse full content directly
        val parsed = runCatching { JsonParser.parseString(content) }.getOrNull()
        if (parsed != null && parsed.isJsonArray) {
            return content
        }
        // Find the first [ and last ], extract everything between
        val start = content.indexOf('[')
        val end = content.lastIndexOf(']')
        if (start >= 0 && end > start) {
            val extracted = content.substring(start, end + 1)
            Log.d(TAG, "Extracted JSON array from wrapped content")
            return extracted
        }
        Log.e(TAG, "No JSON array found in response. Full content:\n$content")
        throw IllegalStateException("Agnes storyboard response is not JSON")
    }

    private fun buildUserPrompt(project: DramaProject, script: String): String {
        val sceneCount = countScenes(script)
        val shotCountHint = if (sceneCount > 0) {
            "Script contains $sceneCount scene headers (## S01, ## S02 ...). Generate exactly one storyboard shot per scene, in order."
        } else {
            "Expected shot count: ${project.shotCount}"
        }
        return """
            Project title: ${project.title}
            Aspect ratio: ${project.aspectRatio}
            $shotCountHint
            Default shot duration seconds: ${project.shotDurationSeconds}

            Script:
            $script

            Return only a JSON array. Each item must use these keys: shot_number, scene, action, dialogue, camera, image_prompt, video_prompt, duration_seconds.
        """.trimIndent()
    }

    /**
     * Count scene headers in rewritten script (format: `## S01 | ...`, `## S02 | ...`).
     * Returns 0 if the script has no scene headers (i.e. it's from the old generate flow).
     */
    private fun countScenes(script: String): Int {
        return SCENE_HEADER_REGEX.findAll(script).count()
    }

    private data class StoryboardItem(
        @SerializedName("shot_number") val shotNumber: String?,
        val scene: String?,
        val action: String?,
        val dialogue: String?,
        val camera: String?,
        @SerializedName("image_prompt") val imagePrompt: String?,
        @SerializedName("video_prompt") val videoPrompt: String?,
        @SerializedName("duration_seconds") val durationSeconds: String?
    )

    companion object {
        private const val TAG = "AgnesStoryboardRepository"
        private const val SYSTEM_PROMPT = "You convert short-drama scripts into production storyboard JSON for mobile vertical video. Return JSON only."
        // Matches scene headers in rewritten scripts: `## S01 | ...`, `## S02 · ...`, etc.
        private val SCENE_HEADER_REGEX = Regex("(?m)^##\\s*S\\d+\\b")
    }
}
