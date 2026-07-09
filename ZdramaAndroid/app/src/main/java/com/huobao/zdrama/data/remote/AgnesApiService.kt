package com.huobao.zdrama.data.remote

import com.google.gson.JsonElement
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

interface AgnesApiService {
    @POST("v1/chat/completions")
    suspend fun createChatCompletion(@Body request: ChatCompletionRequest): JsonElement

    @POST("v1/images/generations")
    suspend fun generateImage(@Body request: ImageGenerationRequest): ImageGenerationResponse

    @POST("v1/videos")
    suspend fun generateVideo(@Body request: VideoGenerationRequest): VideoGenerationResponse

    @GET("v1/videos/{taskId}")
    suspend fun getVideo(@Path("taskId") taskId: String): VideoPollResponse
}

data class ChatCompletionRequest(
    val model: String,
    val messages: List<ChatMessage>,
    val temperature: Double,
    val max_tokens: Int
)

data class ChatMessage(
    val role: String,
    val content: String
)

data class ChatCompletionResponse(
    val id: String?,
    val choices: List<ChatChoice>
)

data class ChatChoice(
    val index: Int,
    val message: ChatMessage
)

data class ImageGenerationRequest(
    val model: String,
    val prompt: String,
    val size: String,
    val n: Int,
    @SerializedName("extra_body") val extraBody: ImageExtraBody
)

data class ImageExtraBody(
    @SerializedName("response_format") val responseFormat: String
)

data class ImageGenerationResponse(
    val id: String?,
    @SerializedName("task_id") val taskId: String?,
    val data: List<ImageGenerationData>?,
    val url: String?
)

data class ImageGenerationData(
    val url: String?,
    @SerializedName("b64_json") val base64: String?
)

data class VideoGenerationRequest(
    val model: String,
    val prompt: String,
    @SerializedName("num_frames") val numFrames: Int,
    @SerializedName("frame_rate") val frameRate: Int,
    val width: Int,
    val height: Int,
    val image: String?,
    val mode: String?
)

data class VideoGenerationResponse(
    val id: String?,
    @SerializedName("task_id") val taskId: String?,
    val status: String?,
    @SerializedName("video_id") val videoId: String?,
    @SerializedName("remixed_from_video_id") val remixedFromVideoId: String?,
    @SerializedName("video_url") val videoUrl: String?,
    val url: String?,
    val error: JsonElement?
)

data class VideoPollResponse(
    val status: String?,
    @SerializedName("remixed_from_video_id") val remixedFromVideoId: String?,
    @SerializedName("video_url") val videoUrl: String?,
    val url: String?,
    val error: JsonElement?
)
