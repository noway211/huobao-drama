package com.huobao.zdrama.data.repository

import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.ChatCompletionRequest
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.settings.AgnesSettings

class AgnesConnectionRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory()
) {
    suspend fun testTextModel(settings: AgnesSettings): Result<Unit> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.textModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Text model is required"))
        }
        return runCatching {
            val service = clientFactory.create(settings)
            service.createChatCompletion(
                ChatCompletionRequest(
                    model = settings.textModel,
                    messages = listOf(ChatMessage(role = "user", content = "ping")),
                    temperature = 0.0,
                    max_tokens = 8
                )
            )
        }.map { Unit }
    }
}
