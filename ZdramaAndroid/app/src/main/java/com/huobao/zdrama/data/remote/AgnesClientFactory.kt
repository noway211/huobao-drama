package com.huobao.zdrama.data.remote

import com.google.gson.GsonBuilder
import com.huobao.zdrama.data.settings.AgnesSettings
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

class AgnesClientFactory {
    fun create(settings: AgnesSettings): AgnesApiService {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        val okHttpClient = OkHttpClient.Builder()
            .addInterceptor(AgnesAuthInterceptor(object : ApiKeyProvider {
                override fun getApiKey(): String? = settings.apiKey
            }))
            .addInterceptor(loggingInterceptor)
            .connectTimeout(settings.requestTimeoutSeconds, TimeUnit.SECONDS)
            .readTimeout(settings.requestTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(settings.requestTimeoutSeconds, TimeUnit.SECONDS)
            .build()

        val gson = GsonBuilder().create()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(settings.baseUrl))
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
            .create(AgnesApiService::class.java)
    }

    private fun normalizeBaseUrl(value: String): String {
        val trimmed = value.trim().ifBlank { AgnesSettings.DEFAULT_BASE_URL }
        return if (trimmed.endsWith("/")) trimmed else "$trimmed/"
    }
}
