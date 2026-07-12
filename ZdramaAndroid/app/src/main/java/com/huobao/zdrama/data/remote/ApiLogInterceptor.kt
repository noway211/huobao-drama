package com.huobao.zdrama.data.remote

import okhttp3.Interceptor
import okhttp3.Response
import okio.Buffer

/**
 * 记录每次 API 调用的完整请求/响应 body 到 [ApiLogStore]。
 *
 * 关键:不消费原 body 流。
 * - 请求 body 通过 writeTo(新 Buffer) 读副本。
 * - 响应 body 通过 peekBody(limit) 读副本,Retrofit 仍能正常解析。
 * 单条 body 超长按 MAX_BODY_BYTES 截断。
 * 只记 body,不记 header,避免泄露 Authorization/API Key。
 *
 * 脱敏:
 * - data URI 中的 base64 内容替换为 `<base64:{len} bytes>`,避免日志被 MB 级图片数据淹没。
 */
class ApiLogInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val startTime = System.currentTimeMillis()
        val requestBody = readRequestBody(request)

        val response = try {
            chain.proceed(request)
        } catch (e: Exception) {
            ApiLogStore.add(
                ApiLogEntry(
                    timestamp = startTime,
                    method = request.method,
                    url = request.url.toString(),
                    statusCode = null,
                    durationMs = System.currentTimeMillis() - startTime,
                    requestBody = requestBody,
                    responseBody = null,
                    errorMessage = e.message ?: e.javaClass.simpleName,
                    isSuccess = false
                )
            )
            throw e
        }

        val durationMs = System.currentTimeMillis() - startTime
        val responseBody = readResponseBody(response)
        ApiLogStore.add(
            ApiLogEntry(
                timestamp = startTime,
                method = request.method,
                url = request.url.toString(),
                statusCode = response.code,
                durationMs = durationMs,
                requestBody = requestBody,
                responseBody = responseBody,
                errorMessage = null,
                isSuccess = response.isSuccessful
            )
        )
        return response
    }

    private fun readRequestBody(request: okhttp3.Request): String? {
        val body = request.body ?: return null
        return runCatching {
            val buffer = Buffer()
            body.writeTo(buffer)
            val raw = buffer.readUtf8()
            truncateBody(sanitize(raw))
        }.getOrNull()
    }

    private fun readResponseBody(response: Response): String? {
        return runCatching {
            val peeked = response.peekBody(MAX_BODY_BYTES)
            truncateBody(sanitize(peeked.string()))
        }.getOrNull()
    }

    private fun sanitize(body: String): String {
        // 把 "data:image/xxx;base64,{很长的payload}" 换成 "data:image/xxx;base64,<base64:{len} bytes>"
        return BASE64_DATA_URI.replace(body) { match ->
            val prefix = match.groupValues[1]
            val payload = match.groupValues[2]
            "$prefix<base64:${payload.length} bytes>"
        }
    }

    private fun truncateBody(text: String): String {
        return if (text.length > MAX_BODY_CHARS) {
            text.take(MAX_BODY_CHARS) + TRUNCATED_SUFFIX
        } else {
            text
        }
    }

    companion object {
        private const val MAX_BODY_BYTES = 32L * 1024
        private const val MAX_BODY_CHARS = 32 * 1024
        private const val TRUNCATED_SUFFIX = "…（已截断）"
        private val BASE64_DATA_URI =
            Regex("(data:[a-zA-Z0-9/+.-]+;base64,)([A-Za-z0-9+/=]+)")
    }
}
