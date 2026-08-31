package com.huobao.zdrama.data.repository

import android.util.Log
import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.ImageExtraBody
import com.huobao.zdrama.data.remote.ImageGenerationRequest
import com.huobao.zdrama.data.remote.ImageReferenceResolver
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.StoryboardShot

class AgnesImageRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory()
) {
    suspend fun generateImage(settings: AgnesSettings, shot: StoryboardShot): Result<String> {
        return generateImage(settings, shot.imagePrompt)
    }

    /**
     * 生成图片。referenceImages 为可选的参考图（本地路径或 URL），传入后走图生图流程
     * （extra_body.image），全部解析失败时自动回退文生图。与 Harmony 端语义一致。
     */
    suspend fun generateImage(
        settings: AgnesSettings,
        prompt: String,
        referenceImages: List<String>? = null
    ): Result<String> {
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
            // 参考图解析：本地路径 → 压缩 base64 data URI；data/http(s) 透传
            val referenceImagesResolved = if (!referenceImages.isNullOrEmpty()) {
                val valid = mutableListOf<String>()
                for (ref in referenceImages) {
                    ImageReferenceResolver.resolve(ref)?.let { valid.add(it) }
                }
                if (valid.isEmpty()) {
                    Log.w(TAG, "All ${referenceImages.size} reference images failed to resolve, fall back to text-to-image")
                    null
                } else {
                    valid
                }
            } else {
                null
            }

            val response = clientFactory.create(settings).generateImage(
                ImageGenerationRequest(
                    model = settings.imageModel,
                    prompt = prompt,
                    size = DEFAULT_IMAGE_SIZE,
                    n = 1,
                    extraBody = ImageExtraBody(
                        responseFormat = "url",
                        image = referenceImagesResolved
                    )
                )
            )
            val imageUrl = response.data?.firstOrNull()?.url ?: response.url
            imageUrl?.takeIf { it.isNotBlank() }
                ?: throw IllegalStateException("No image URL in Agnes response")
        }
    }

    suspend fun generateImageForCharacter(settings: AgnesSettings, prompt: String): Result<String> {
        return generateImage(settings, prompt)
    }

    companion object {
        private const val TAG = "AgnesImageRepository"
        private const val DEFAULT_IMAGE_SIZE = "1024x768"
    }
}
