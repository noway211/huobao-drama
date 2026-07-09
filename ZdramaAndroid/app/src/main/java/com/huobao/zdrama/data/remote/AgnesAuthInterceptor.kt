package com.huobao.zdrama.data.remote

import okhttp3.Interceptor
import okhttp3.Response

interface ApiKeyProvider {
    fun getApiKey(): String?
}

class AgnesAuthInterceptor(
    private val apiKeyProvider: ApiKeyProvider
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()
        val apiKey = apiKeyProvider.getApiKey()

        val requestBuilder = originalRequest.newBuilder()
        if (!apiKey.isNullOrBlank()) {
            requestBuilder.header("Authorization", "Bearer $apiKey")
        }

        return chain.proceed(requestBuilder.build())
    }
}
