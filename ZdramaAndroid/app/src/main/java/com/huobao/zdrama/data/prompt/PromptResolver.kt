package com.huobao.zdrama.data.prompt

/**
 * 自定义提示词与默认值的统一 fallback 解析。
 * - 空串 / 纯空白 / null → 返回 [default]
 * - 其它情况 → 返回 trim 后的自定义值
 *
 * 与 Harmony 端 (settings.customXxx ?? '').trim() || DEFAULT 语义一致。
 */
object PromptResolver {
    fun resolve(custom: String?, default: String): String {
        val trimmed = custom?.trim().orEmpty()
        return trimmed.ifEmpty { default }
    }
}
