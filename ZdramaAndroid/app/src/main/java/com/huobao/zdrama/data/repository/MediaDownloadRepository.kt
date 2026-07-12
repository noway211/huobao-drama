package com.huobao.zdrama.data.repository

import android.content.Context
import com.huobao.zdrama.data.remote.ApiLogEntry
import com.huobao.zdrama.data.remote.ApiLogStore
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class MediaDownloadRepository(
    context: Context,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(DOWNLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(DOWNLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(DOWNLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()
) {
    private val appContext = context.applicationContext

    fun deleteGeneratedMedia(projectId: Long): Boolean {
        val targetDir = File(appContext.filesDir, "generated/$projectId")
        return !targetDir.exists() || targetDir.deleteRecursively()
    }

    fun downloadToGeneratedMedia(
        projectId: Long,
        shotId: Long,
        url: String,
        mediaType: MediaType
    ): Result<String> {
        if (url.isBlank()) return Result.failure(IllegalArgumentException("Media URL is empty"))
        val extension = extensionFromUrl(url, mediaType)
        val targetDir = File(appContext.filesDir, "generated/$projectId")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            return Result.failure(IOException("Unable to create media directory"))
        }
        val targetFile = File(targetDir, "shot_${shotId}_${mediaType.fileNamePart}.$extension")
        val request = Request.Builder().url(url).build()
        val startTime = System.currentTimeMillis()
        return runCatching {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    ApiLogStore.add(
                        ApiLogEntry(
                            timestamp = startTime,
                            method = "GET",
                            url = url,
                            statusCode = response.code,
                            durationMs = System.currentTimeMillis() - startTime,
                            requestBody = "download ${mediaType.name} → project=$projectId shot=$shotId",
                            responseBody = null,
                            errorMessage = "HTTP ${response.code}",
                            isSuccess = false
                        )
                    )
                    throw IOException("Media download failed: HTTP ${response.code}")
                }
                val body = response.body ?: throw IOException("Media download failed: empty response")
                targetFile.outputStream().use { output ->
                    body.byteStream().use { input ->
                        input.copyTo(output)
                    }
                }
            }
            val bytes = targetFile.length()
            ApiLogStore.add(
                ApiLogEntry(
                    timestamp = startTime,
                    method = "GET",
                    url = url,
                    statusCode = 200,
                    durationMs = System.currentTimeMillis() - startTime,
                    requestBody = "download ${mediaType.name} → project=$projectId shot=$shotId",
                    responseBody = "saved ${formatBytes(bytes)} to ${targetFile.absolutePath}",
                    errorMessage = null,
                    isSuccess = true
                )
            )
            targetFile.absolutePath
        }.onFailure { throwable ->
            // 记录异常型失败(网络中断、write 失败)。HTTP 错误码已在上面记录,不重复。
            if (throwable !is IOException || throwable.message?.startsWith("Media download failed: HTTP") != true) {
                ApiLogStore.add(
                    ApiLogEntry(
                        timestamp = startTime,
                        method = "GET",
                        url = url,
                        statusCode = null,
                        durationMs = System.currentTimeMillis() - startTime,
                        requestBody = "download ${mediaType.name} → project=$projectId shot=$shotId",
                        responseBody = null,
                        errorMessage = throwable.message ?: throwable.javaClass.simpleName,
                        isSuccess = false
                    )
                )
            }
        }
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "${bytes}B"
        if (bytes < 1024 * 1024) return "${bytes / 1024}KB"
        val mb = bytes.toDouble() / (1024.0 * 1024.0)
        return "%.2fMB".format(mb)
    }

    private fun extensionFromUrl(url: String, mediaType: MediaType): String {
        val path = url.substringBefore('?').substringBefore('#')
        val extension = path.substringAfterLast('.', missingDelimiterValue = "")
            .lowercase()
            .takeIf { it.length in 2..5 && it.all { char -> char.isLetterOrDigit() } }
        return extension ?: mediaType.defaultExtension
    }

    companion object {
        private const val DOWNLOAD_TIMEOUT_SECONDS = 120L
    }

    enum class MediaType(
        val fileNamePart: String,
        val defaultExtension: String
    ) {
        IMAGE("image", "jpg"),
        VIDEO("video", "mp4")
    }
}
