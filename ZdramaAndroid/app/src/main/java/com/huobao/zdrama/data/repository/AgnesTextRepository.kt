package com.huobao.zdrama.data.repository

import android.util.Log
import com.huobao.zdrama.data.prompt.PromptDefaults
import com.huobao.zdrama.data.prompt.PromptResolver
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
                        ChatMessage(role = "system", content = PromptResolver.resolve(settings.customScriptCreatePrompt, PromptDefaults.SCRIPT_CREATE_PROMPT)),
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
        return """请根据以下项目信息创作一部短视频短剧剧本。

项目标题：${project.title}
故事提示词：${project.prompt}
风格：${project.style}
目标受众：${project.targetAudience}
画幅比例：${project.aspectRatio}
镜头数量：${project.shotCount}
单镜头时长：${project.shotDurationSeconds}秒"""
    }

    suspend fun rewriteScript(settings: AgnesSettings, rawContent: String): Result<String> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.textModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Text model is required"))
        }
        if (rawContent.isBlank()) {
            return Result.failure(IllegalArgumentException("Raw content is empty"))
        }

        return runCatching {
            val service = clientFactory.create(settings)
            val response = service.createChatCompletion(
                ChatCompletionRequest(
                    model = settings.textModel,
                    messages = listOf(
                        ChatMessage(role = "system", content = PromptResolver.resolve(settings.customScriptRewritePrompt, PromptDefaults.SCRIPT_REWRITE_PROMPT)),
                        ChatMessage(role = "user", content = buildRewriteUserPrompt(rawContent))
                    ),
                    temperature = 0.7,
                    max_tokens = 6000
                )
            )
            Log.d(TAG, "rewrite response structure: ${ChatResponseTextExtractor.describe(response)}")
            ChatResponseTextExtractor.extract(response)
                .ifBlank { throw IllegalStateException("Agnes 未返回改写内容，请检查文本模型是否支持 chat/completions") }
        }
    }

    private fun buildRewriteUserPrompt(rawContent: String): String {
        return """请将以下内容改写为格式化短剧剧本。

【原始内容】
$rawContent"""
    }

    /**
     * 通用 chat/completions 调用。返回原始 JSON 响应字符串，由调用方自行用
     * ChatResponseTextExtractor 提取 content 文本。这样能保留对 reasoning_content、
     * output_text 等多种返回格式的兼容性。
     */
    suspend fun postChat(
        settings: AgnesSettings,
        messages: List<ChatMessage>,
        temperature: Double,
        maxTokens: Int
    ): Result<String> {
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
                    messages = messages,
                    temperature = temperature,
                    max_tokens = maxTokens
                )
            )
            Log.d(TAG, "postChat response structure: ${ChatResponseTextExtractor.describe(response)}")
            response.toString()
        }
    }

    companion object {
        private const val TAG = "AgnesTextRepository"
    }
}
