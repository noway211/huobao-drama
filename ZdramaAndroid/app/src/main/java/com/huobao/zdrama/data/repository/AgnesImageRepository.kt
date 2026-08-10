package com.huobao.zdrama.data.repository

import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.ImageExtraBody
import com.huobao.zdrama.data.remote.ImageGenerationRequest
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.StoryboardShot

class AgnesImageRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory()
) {
    suspend fun generateImage(settings: AgnesSettings, shot: StoryboardShot): Result<String> {
        return generateImageForCharacter(settings, shot.imagePrompt)
    }

    suspend fun generateImageForCharacter(settings: AgnesSettings, prompt: String): Result<String> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.imageModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Image model is required"))
        }
        if (prompt.isBlank()) {
            return Result.failure(IllegalArgumentException("Image prompt is required"))
        }

        return runCatching {
            val response = clientFactory.create(settings).generateImage(
                ImageGenerationRequest(
                    model = settings.imageModel,
                    prompt = prompt,
                    size = DEFAULT_IMAGE_SIZE,
                    n = 1,
                    extraBody = ImageExtraBody(responseFormat = "url")
                )
            )
            val imageUrl = response.data?.firstOrNull()?.url ?: response.url
            imageUrl?.takeIf { it.isNotBlank() }
                ?: throw IllegalStateException("No image URL in Agnes response")
        }
    }

    companion object {
        private const val DEFAULT_IMAGE_SIZE = "1024x768"
    }
}
