package com.huobao.zdrama.data.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

class AgnesSettingsStore(context: Context) {
    private val appContext = context.applicationContext
    private val securePreferences: SharedPreferences by lazy { createSecurePreferences() }
    private val plainPreferences: SharedPreferences by lazy {
        appContext.getSharedPreferences(PLAIN_PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun load(): AgnesSettings {
        val defaults = AgnesSettings.defaults()
        return AgnesSettings(
            apiKey = securePreferences.getString(KEY_API_KEY, defaults.apiKey).orEmpty(),
            baseUrl = plainPreferences.getString(KEY_BASE_URL, defaults.baseUrl).orEmpty().ifBlank { defaults.baseUrl },
            textModel = plainPreferences.getString(KEY_TEXT_MODEL, defaults.textModel).orEmpty(),
            imageModel = plainPreferences.getString(KEY_IMAGE_MODEL, defaults.imageModel).orEmpty().ifBlank { defaults.imageModel },
            videoModel = plainPreferences.getString(KEY_VIDEO_MODEL, defaults.videoModel).orEmpty().ifBlank { defaults.videoModel },
            requestTimeoutSeconds = plainPreferences.getLong(KEY_TIMEOUT_SECONDS, defaults.requestTimeoutSeconds),
            customScriptCreatePrompt = plainPreferences.getString(KEY_CUSTOM_SCRIPT_CREATE_PROMPT, null),
            customScriptRewritePrompt = plainPreferences.getString(KEY_CUSTOM_SCRIPT_REWRITE_PROMPT, null),
            customCharacterExtractPrompt = plainPreferences.getString(KEY_CUSTOM_CHARACTER_EXTRACT_PROMPT, null),
            customStoryboardPrompt = plainPreferences.getString(KEY_CUSTOM_STORYBOARD_PROMPT, null)
        )
    }

    fun save(settings: AgnesSettings) {
        securePreferences.edit()
            .putString(KEY_API_KEY, settings.apiKey.trim())
            .apply()
        plainPreferences.edit()
            .putString(KEY_BASE_URL, normalizeBaseUrl(settings.baseUrl))
            .putString(KEY_TEXT_MODEL, settings.textModel.trim())
            .putString(KEY_IMAGE_MODEL, settings.imageModel.trim())
            .putString(KEY_VIDEO_MODEL, settings.videoModel.trim())
            .putLong(KEY_TIMEOUT_SECONDS, settings.requestTimeoutSeconds)
            .putString(KEY_CUSTOM_SCRIPT_CREATE_PROMPT, settings.customScriptCreatePrompt?.trim().orEmpty().ifEmpty { null })
            .putString(KEY_CUSTOM_SCRIPT_REWRITE_PROMPT, settings.customScriptRewritePrompt?.trim().orEmpty().ifEmpty { null })
            .putString(KEY_CUSTOM_CHARACTER_EXTRACT_PROMPT, settings.customCharacterExtractPrompt?.trim().orEmpty().ifEmpty { null })
            .putString(KEY_CUSTOM_STORYBOARD_PROMPT, settings.customStoryboardPrompt?.trim().orEmpty().ifEmpty { null })
            .apply()
    }

    fun hasApiKey(): Boolean {
        return load().apiKey.isNotBlank()
    }

    private fun createSecurePreferences(): SharedPreferences {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        return EncryptedSharedPreferences.create(
            SECURE_PREFS_NAME,
            masterKeyAlias,
            appContext,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private fun normalizeBaseUrl(value: String): String {
        val trimmed = value.trim().ifBlank { AgnesSettings.DEFAULT_BASE_URL }
        return if (trimmed.endsWith("/")) trimmed else "$trimmed/"
    }

    companion object {
        private const val SECURE_PREFS_NAME = "agnes_secure_settings"
        private const val PLAIN_PREFS_NAME = "agnes_plain_settings"
        private const val KEY_API_KEY = "api_key"
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_TEXT_MODEL = "text_model"
        private const val KEY_IMAGE_MODEL = "image_model"
        private const val KEY_VIDEO_MODEL = "video_model"
        private const val KEY_TIMEOUT_SECONDS = "timeout_seconds"
        // 4 个 LLM 流程的自定义系统提示词（覆盖 PromptDefaults 中的默认值）
        private const val KEY_CUSTOM_SCRIPT_CREATE_PROMPT = "custom_script_create_prompt"
        private const val KEY_CUSTOM_SCRIPT_REWRITE_PROMPT = "custom_script_rewrite_prompt"
        private const val KEY_CUSTOM_CHARACTER_EXTRACT_PROMPT = "custom_character_extract_prompt"
        private const val KEY_CUSTOM_STORYBOARD_PROMPT = "custom_storyboard_prompt"
    }
}
