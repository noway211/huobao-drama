package com.huobao.zdrama.data.repository

import android.content.Context
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException

class MediaDownloadRepository(
    context: Context,
    private val client: OkHttpClient = OkHttpClient()
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
        return runCatching {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw IOException("Media download failed: HTTP ${response.code}")
                val body = response.body ?: throw IOException("Media download failed: empty response")
                targetFile.outputStream().use { output ->
                    body.byteStream().use { input ->
                        input.copyTo(output)
                    }
                }
            }
            targetFile.absolutePath
        }
    }

    private fun extensionFromUrl(url: String, mediaType: MediaType): String {
        val path = url.substringBefore('?').substringBefore('#')
        val extension = path.substringAfterLast('.', missingDelimiterValue = "")
            .lowercase()
            .takeIf { it.length in 2..5 && it.all { char -> char.isLetterOrDigit() } }
        return extension ?: mediaType.defaultExtension
    }

    enum class MediaType(
        val fileNamePart: String,
        val defaultExtension: String
    ) {
        IMAGE("image", "jpg"),
        VIDEO("video", "mp4")
    }
}
