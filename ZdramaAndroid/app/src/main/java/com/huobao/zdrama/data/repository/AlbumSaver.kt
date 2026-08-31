package com.huobao.zdrama.data.repository

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 把沙盒内 mp4 视频保存到系统视频相册（移植自 Harmony 端 AlbumSaver.ets）。
 *
 * 流程：ContentResolver.insert 到 MediaStore.Video → openOutputStream 拷贝 → 返回 content URI。
 *
 * 权限策略（对应 Harmony SaveButton 安全控件自动授权的效果）：
 * - API >= 29（Android 10+）：scoped storage 直写相册，无需任何权限
 * - API < 29：调用方必须先持有 WRITE_EXTERNAL_STORAGE 运行时权限
 *   （manifest 中已声明 maxSdkVersion="28"）
 */
object AlbumSaver {

    /** 相册目录：Movies（系统相册的视频分类）。 */
    private const val RELATIVE_PATH = "Movies"

    /** 把中文/带空格的标题清洗成相册里能显示的名字（对齐 Harmony 端 sanitizeDisplayTitle）。 */
    fun sanitizeDisplayTitle(raw: String?): String {
        val cleaned = raw?.replace(Regex("[\\\\/:*?\"<>|]"), "_")?.trim().orEmpty()
        if (cleaned.isEmpty()) return "final"
        return cleaned.take(80)
    }

    /**
     * 把本地 mp4 保存到系统相册。
     *
     * @param localPath 沙盒内绝对路径（例如 filesDir/generated/{projectId}/final_video.mp4）
     * @param displayTitle 相册里显示的标题（自动追加时间戳和 .mp4 后缀，与 Harmony 端一致）
     * @return Result.success(相册 content URI) / Result.failure(原因)
     */
    suspend fun saveVideo(context: Context, localPath: String, displayTitle: String): Result<String> =
        withContext(Dispatchers.IO) {
            runCatching {
                // 前置校验：文件必须存在且非空（同 Harmony 端）
                val file = File(localPath)
                if (!file.exists() || file.length() <= 0) {
                    throw IllegalStateException("本地文件不存在或已删除")
                }

                val resolver = context.contentResolver
                val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                val displayName = "${sanitizeDisplayTitle(displayTitle)}_$stamp.mp4"
                val uri = insertVideoAsset(resolver, displayName)
                    ?: throw IllegalStateException("相册写入被拒绝")
                resolver.openOutputStream(uri)?.use { out ->
                    file.inputStream().use { ins -> ins.copyTo(out) }
                } ?: throw IllegalStateException("无法打开相册写入流")
                uri.toString()
            }
        }

    /** 在媒体库创建空 video 资产并返回其 content URI。 */
    private fun insertVideoAsset(resolver: android.content.ContentResolver, displayName: String): Uri? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, RELATIVE_PATH)
            }
            return resolver.insert(
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                values
            )
        }
        // API < 29：旧版写法，INSERT 到外部存储 Movies 目录（需 WRITE_EXTERNAL_STORAGE）
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建 Movies 目录")
        }
        val dest = File(dir, displayName)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.DATA, dest.absolutePath)
        }
        return resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
    }
}