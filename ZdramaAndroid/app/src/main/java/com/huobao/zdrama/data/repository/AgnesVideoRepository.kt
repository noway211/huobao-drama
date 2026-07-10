package com.huobao.zdrama.data.repository

import com.google.gson.JsonElement
import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.VideoGenerationRequest
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.StoryboardShot
import kotlinx.coroutines.delay

class AgnesVideoRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory()
) {
    suspend fun generateVideo(
        settings: AgnesSettings,
        shot: StoryboardShot,
        imageReference: String? = null
    ): Result<VideoGenerationResult> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.videoModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Video model is required"))
        }
        val imageUrl = imageReference ?: shot.imageUrl.orEmpty()
        if (imageUrl.isBlank()) {
            return Result.failure(IllegalArgumentException("Generate image before video"))
        }

        return runCatching {
            val service = clientFactory.create(settings)
            val response = service.generateVideo(
                VideoGenerationRequest(
                    model = settings.videoModel,
                    prompt = buildPrompt(shot),
                    numFrames = durationToNumFrames(shot.durationSeconds),
                    frameRate = FRAME_RATE,
                    width = DEFAULT_WIDTH,
                    height = DEFAULT_HEIGHT,
                    image = imageUrl,
                    mode = "ti2vid"
                )
            )

            val immediateUrl = response.remixedFromVideoId ?: response.videoUrl ?: response.url ?: response.videoId
            if (response.status == "completed" && !immediateUrl.isNullOrBlank()) {
                return@runCatching VideoGenerationResult(taskId = response.taskId ?: response.id, videoUrl = immediateUrl)
            }

            val taskId = response.taskId ?: response.id
                ?: throw IllegalStateException("No task_id/id in Agnes video response")
            pollVideo(service, taskId)
        }
    }

    private suspend fun pollVideo(
        service: com.huobao.zdrama.data.remote.AgnesApiService,
        taskId: String
    ): VideoGenerationResult {
        repeat(MAX_POLL_COUNT) {
            delay(POLL_INTERVAL_MS)
            val response = service.getVideo(taskId)
            when (response.status) {
                "completed" -> {
                    val videoUrl = response.remixedFromVideoId ?: response.videoUrl ?: response.url
                    if (videoUrl.isNullOrBlank()) {
                        throw IllegalStateException("Agnes video completed without URL")
                    }
                    return VideoGenerationResult(taskId = taskId, videoUrl = videoUrl)
                }
                "failed" -> throw IllegalStateException(parseError(response.error))
            }
        }
        throw IllegalStateException("Video generation timed out")
    }

    private fun buildPrompt(shot: StoryboardShot): String {
        return listOf(shot.videoPrompt, shot.action, shot.camera)
            .filter { it.isNotBlank() }
            .joinToString(separator = "。") + "。请使用中文对白与中文旁白。"
    }

    private fun durationToNumFrames(durationSeconds: Int): Int {
        val requested = durationSeconds.coerceAtLeast(1) * FRAME_RATE
        val capped = requested.coerceAtMost(MAX_NUM_FRAMES)
        val n = ((capped - 1) / 8).coerceAtLeast(1)
        return n * 8 + 1
    }

    private fun parseError(error: JsonElement?): String {
        if (error == null || error.isJsonNull) return "Video generation failed"
        if (error.isJsonPrimitive) return error.asString
        return error.asJsonObject.get("message")?.asString ?: error.toString()
    }

    companion object {
        private const val FRAME_RATE = 24
        private const val MAX_NUM_FRAMES = 441
        private const val DEFAULT_WIDTH = 768
        private const val DEFAULT_HEIGHT = 1152
        private const val POLL_INTERVAL_MS = 10_000L
        private const val MAX_POLL_COUNT = 60
    }
}

data class VideoGenerationResult(
    val taskId: String?,
    val videoUrl: String
)
