package com.huobao.zdrama.data.settings

data class AgnesSettings(
    val apiKey: String,
    val baseUrl: String,
    val textModel: String,
    val imageModel: String,
    val videoModel: String,
    val requestTimeoutSeconds: Long
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
