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
                        ChatMessage(role = "system", content = REWRITE_SYSTEM_PROMPT),
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
        private const val SYSTEM_PROMPT = """你是一位专业的短剧编剧。请根据用户提供的项目信息创作格式化短剧剧本。

格式规范：
- 场景头：## S编号 | 内景/外景 · 地点 | 时间段
- 动作描写：自然段落，增强画面感，不包含镜头语言
- 对白格式：角色名：（状态/表情）台词内容
- 每个场景控制在 30-60 秒内容
- 场景编号连续递增（S01, S02, S03...）

创作原则：
- 根据标题和故事提示词展开完整剧本
- 设计有吸引力的开场钩子
- 用对白推动情节，减少旁白
- 心理描写转化为角色表情/动作"""
        private const val REWRITE_SYSTEM_PROMPT = """你是一位专业的短剧编剧。请将用户提供的原始内容改写为格式化短剧剧本。

格式规范：
- 场景头：## S编号 | 内景/外景 · 地点 | 时间段
- 动作描写：自然段落，增强画面感，不包含镜头语言
- 对白格式：角色名：（状态/表情）台词内容
- 每个场景控制在 30-60 秒内容
- 场景编号连续递增（S01, S02, S03...）

改写原则：
- 保留核心情节，不改变主线故事和角色关系
- 将叙述性文字转化为可视化的场景描写
- 用对白推动情节，减少旁白
- 心理描写转化为角色表情/动作
- 长段叙述拆分为多个短场景"""
    }
}
