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
        return downloadToFile(
            url = url,
            targetFile = targetFile,
            mediaType = mediaType,
            projectId = projectId,
            label = "shot=$shotId"
        )
    }

    fun downloadCharImage(
        projectId: Long,
        characterId: Long,
        url: String
    ): Result<String> {
        if (url.isBlank()) return Result.failure(IllegalArgumentException("Media URL is empty"))
        val mediaType = MediaType.IMAGE
        val extension = extensionFromUrl(url, mediaType)
        val targetDir = File(appContext.filesDir, "generated/$projectId")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            return Result.failure(IOException("Unable to create media directory"))
        }
        val targetFile = File(targetDir, "char_${characterId}_${mediaType.fileNamePart}.$extension")
        val rawResult = downloadToFile(
            url = url,
            targetFile = targetFile,
            mediaType = mediaType,
            projectId = projectId,
            label = "char=$characterId"
        )
        // 校验文件 magic byte，避免下载到 HTML/错误页
        return rawResult.fold(
            onSuccess = { path -> validateImageMagicBytes(path) },
            onFailure = { Result.failure(it) }
        )
    }

    private fun downloadToFile(
        url: String,
        targetFile: File,
        mediaType: MediaType,
        projectId: Long,
        label: String
    ): Result<String> {
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
                            requestBody = "download ${mediaType.name} → project=$projectId $label",
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
                    requestBody = "download ${mediaType.name} → project=$projectId $label",
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
                        requestBody = "download ${mediaType.name} → project=$projectId $label",
                        responseBody = null,
                        errorMessage = throwable.message ?: throwable.javaClass.simpleName,
                        isSuccess = false
                    )
                )
            }
        }
    }

    private fun validateImageMagicBytes(path: String): Result<String> {
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            file.delete()
            return Result.failure(IOException("下载文件为空：IMAGE"))
        }
        val header = ByteArray(16)
        val read = runCatching { file.inputStream().use { it.read(header) } }.getOrDefault(-1)
        if (read < 8) {
            file.delete()
            return Result.failure(IOException("下载文件格式异常：IMAGE"))
        }
        val looksLikeImage = isPng(header, read) ||
            isJpeg(header, read) ||
            isWebp(header, read) ||
            isGif(header, read)
        if (!looksLikeImage) {
            file.delete()
            return Result.failure(IOException("下载文件格式异常：IMAGE"))
        }
        return Result.success(path)
    }

    private fun isPng(header: ByteArray, read: Int): Boolean {
        if (read < 8) return false
        val sig = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        for (i in 0 until 8) if (header[i] != sig[i]) return false
        return true
    }

    private fun isJpeg(header: ByteArray, read: Int): Boolean {
        if (read < 3) return false
        return header[0] == 0xFF.toByte() && header[1] == 0xD8.toByte() && header[2] == 0xFF.toByte()
    }

    private fun isWebp(header: ByteArray, read: Int): Boolean {
        if (read < 12) return false
        val riff = "RIFF".toByteArray(Charsets.US_ASCII)
        val webp = "WEBP".toByteArray(Charsets.US_ASCII)
        for (i in 0 until 4) if (header[i] != riff[i]) return false
        for (i in 0 until 4) if (header[8 + i] != webp[i]) return false
        return true
    }

    private fun isGif(header: ByteArray, read: Int): Boolean {
        if (read < 6) return false
        val sig = "GIF8".toByteArray(Charsets.US_ASCII)
        for (i in 0 until 4) if (header[i] != sig[i]) return false
        return header[4] == '7'.code.toByte() || header[4] == '9'.code.toByte()
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
