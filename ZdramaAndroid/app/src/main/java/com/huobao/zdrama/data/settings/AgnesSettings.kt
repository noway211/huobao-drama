package com.huobao.zdrama.data.settings

data class AgnesSettings(
    val apiKey: String,
    val baseUrl: String,
    val textModel: String,
    val imageModel: String,
    val videoModel: String,
    val requestTimeoutSeconds: Long,
    /**
     * 4 个 LLM 流程的自定义系统提示词。
     * - null 或 trim 后为空 → 调用方 fallback 到 PromptDefaults 的常量值
     * - 其它情况 → 用 trim 后的用户值
     * 与 Harmony 端 (settings.customXxx ?? '').trim() || DEFAULT 语义一致。
     */
    val customScriptCreatePrompt: String? = null,
    val customScriptRewritePrompt: String? = null,
    val customCharacterExtractPrompt: String? = null,
    val customStoryboardPrompt: String? = null
) {
    companion object {
        const val DEFAULT_BASE_URL = "https://apihub.agnes-ai.com/"
        const val DEFAULT_IMAGE_MODEL = "agnes-image-2.0-flash"
        const val DEFAULT_VIDEO_MODEL = "agnes-video-v2.0"
        const val DEFAULT_TIMEOUT_SECONDS = 120L

        fun defaults(): AgnesSettings {
            return AgnesSettings(
                apiKey = "",
                baseUrl = DEFAULT_BASE_URL,
                textModel = "",
                imageModel = DEFAULT_IMAGE_MODEL,
                videoModel = DEFAULT_VIDEO_MODEL,
                requestTimeoutSeconds = DEFAULT_TIMEOUT_SECONDS
            )
        }
    }
}
