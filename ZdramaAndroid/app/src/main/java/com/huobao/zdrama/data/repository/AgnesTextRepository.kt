package com.huobao.zdrama.data.repository

import android.util.Log
import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.ChatCompletionRequest
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.remote.ChatResponseTextExtractor
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.DramaProject

class AgnesTextRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory()
) {
    suspend fun generateScript(settings: AgnesSettings, project: DramaProject): Result<String> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.textModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Text model is required"))
        }

        return runCatching {
            val service = clientFactory.create(settings)
            val response = service.createChatCompletion(
                ChatCompletionRequest(
                    model = settings.textModel,
                    messages = listOf(
                        ChatMessage(role = "system", content = SYSTEM_PROMPT),
                        ChatMessage(role = "user", content = buildUserPrompt(project))
                    ),
                    temperature = 0.7,
                    max_tokens = 4000
                )
            )
            Log.d(TAG, "script response structure: ${ChatResponseTextExtractor.describe(response)}")
            ChatResponseTextExtractor.extract(response)
                .ifBlank { throw IllegalStateException("Agnes 未返回脚本文本，请检查文本模型是否支持 chat/completions") }
        }
    }

    private fun buildUserPrompt(project: DramaProject): String {
        return """
            Title: ${project.title}
            Story prompt: ${project.prompt}
            Style: ${project.style}
            Target audience: ${project.targetAudience}
            Aspect ratio: ${project.aspectRatio}
            Shot count: ${project.shotCount}
            Shot duration seconds: ${project.shotDurationSeconds}

            Generate a concise mobile short-drama script. Return numbered shots. For each shot include scene, character action, dialogue, camera direction, and image/video generation notes.
        """.trimIndent()
    }

    companion object {
        private const val TAG = "AgnesTextRepository"
        private const val SYSTEM_PROMPT = "You are an expert short-drama writer for mobile vertical video production."
    }
}
