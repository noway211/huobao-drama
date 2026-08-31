package com.huobao.zdrama.data.remote

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * 角色参考图解析器（移植自 Harmony 端 ImageReferenceResolver.ets）。
 *
 * 把传进来的引用值统一转换成 Agnes 图生图可用的形式：
 * - `data:` / `http(s)://` → 原样透传
 * - 本地文件路径 → 采样解码 → 等比缩放到 768x768 以内 → JPEG(q=68) → base64 data URI
 *
 * 压缩参数（MAX_WIDTH/MAX_HEIGHT=768、JPEG_QUALITY=68）与 Harmony 端及后端
 * image-generation.ts:206-209 对齐。任何一步失败返回 null，调用方回退文生图。
 */
object ImageReferenceResolver {

    private const val MAX_DIMENSION = 768
    private const val JPEG_QUALITY = 68

    fun resolve(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        if (trimmed.startsWith("data:") || trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            return trimmed
        }

        val file = File(trimmed)
        if (!file.exists() || file.length() <= 0) return null

        return runCatching {
            // 采样解码避免大图 OOM
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(trimmed, bounds)
            val options = BitmapFactory.Options().apply {
                inSampleSize = computeSampleSize(bounds.outWidth, bounds.outHeight)
            }
            val bitmap = BitmapFactory.decodeFile(trimmed, options) ?: return null
            val scaled = scaleTo(bitmap)
            if (scaled !== bitmap) bitmap.recycle()

            val bytes = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, bytes)
            scaled.recycle()
            val base64 = Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
            "data:image/jpeg;base64,$base64"
        }.getOrNull()
    }

    /** 2 的幂采样因子：保证采样后长边仍 ≥ MAX_DIMENSION（后续 scaleWithin 再精确缩放）。 */
    private fun computeSampleSize(width: Int, height: Int): Int {
        var sample = 1
        while (width / sample > MAX_DIMENSION || height / sample > MAX_DIMENSION) {
            sample *= 2
        }
        return sample
    }

    /** 长边超过 768 时等比缩小；否则原样返回。 */
    private fun scaleTo(bitmap: Bitmap): Bitmap {
        val maxSide = maxOf(bitmap.width, bitmap.height)
        if (maxSide <= MAX_DIMENSION) return bitmap
        val scale = MAX_DIMENSION.toFloat() / maxSide
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }
}