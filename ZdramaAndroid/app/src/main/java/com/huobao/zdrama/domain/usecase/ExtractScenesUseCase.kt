package com.huobao.zdrama.domain.usecase

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.huobao.zdrama.data.prompt.PromptDefaults
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.remote.ChatResponseTextExtractor
import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.Scene

class ExtractScenesUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesTextRepository: AgnesTextRepository
) {
    suspend fun execute(projectId: Long, episodeId: Long, settings: AgnesSettings): Result<Int> {
        dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))

        val episode = dramaRepository.getEpisodeById(episodeId)
            ?: return Result.failure(IllegalArgumentException("Episode not found"))
        val script = episode.scriptContent
        if (script.isNullOrBlank()) {
            return Result.failure(IllegalArgumentException("请先为本集创作或改写脚本"))
        }

        val existingScenes = dramaRepository.getScenes(projectId)
        val existingHint = if (existingScenes.isNotEmpty()) {
            val listed = existingScenes.joinToString("、") { "${it.location}（${it.time}）" }
            "\n\n项目中已存在场景：$listed。地点和时间都相同则复用；同一地点但时间不同则作为新场景。"
        } else {
            ""
        }

        val userPrompt = """请从以下剧本中提取所有场景，返回 JSON 数组。
每个条目包含：location（地点）、time（时间段）、atmosphere（氛围）、prompt（英文纯背景提示词，不含人物）。
只返回 JSON 数组。

剧本：
$script$existingHint"""

        val rawResult = agnesTextRepository.postChat(
            settings = settings,
            messages = listOf(
                ChatMessage(role = "system", content = PromptDefaults.SCENE_EXTRACT_PROMPT),
                ChatMessage(role = "user", content = userPrompt)
            ),
            temperature = 0.3,
            maxTokens = 4000
        )
        if (rawResult.isFailure) {
            val err = rawResult.exceptionOrNull()?.message ?: "场景提取请求失败"
            return Result.failure(IllegalStateException(err))
        }

        val rawJson = rawResult.getOrThrow()
        val parsedElement = runCatching { Gson().fromJson(rawJson, JsonElement::class.java) }
            .getOrNull() ?: return Result.failure(IllegalStateException("无法解析场景提取结果"))
        val contentText = ChatResponseTextExtractor.extractFinalContent(parsedElement)
        if (contentText.isBlank()) {
            return Result.failure(IllegalStateException("无法解析场景提取结果"))
        }

        var jsonStr = contentText.trim()
        if (!jsonStr.startsWith("[")) {
            val start = jsonStr.indexOf('[')
            val end = jsonStr.lastIndexOf(']')
            if (start >= 0 && end > start) {
                jsonStr = jsonStr.substring(start, end + 1)
            }
        }
        val items: List<Map<String, Any?>> = runCatching {
            val list = Gson().fromJson(jsonStr, List::class.java) ?: return@runCatching emptyList()
            list.filterIsInstance<Map<String, Any?>>()
        }.getOrElse {
            return Result.failure(IllegalStateException("无法解析场景提取结果"))
        }
        if (items.isEmpty()) {
            return Result.failure(IllegalStateException("未从剧本中提取到场景"))
        }

        val now = System.currentTimeMillis()
        Log.i(
            TAG,
            "extractScenes start: project=$projectId episode=${episode.id} " +
                "existing=${existingScenes.size} parsed=${items.size}"
        )
        val scenes = items.mapNotNull { item ->
            val location = (item["location"] as? String)?.trim().orEmpty()
            if (location.isEmpty()) return@mapNotNull null
            Scene(
                id = 0L,
                projectId = projectId,
                episodeId = episode.id,
                location = location,
                time = (item["time"] as? String)?.trim().orEmpty(),
                atmosphere = (item["atmosphere"] as? String).orEmpty(),
                prompt = (item["prompt"] as? String).orEmpty(),
                createdAt = now,
                updatedAt = now
            )
        }
        if (scenes.isEmpty()) {
            return Result.failure(IllegalStateException("未从剧本中提取到场景"))
        }

        dramaRepository.upsertScenes(projectId, scenes)
        Log.i(TAG, "extractScenes done: project=$projectId episode=${episode.id} upserted=${scenes.size}")
        return Result.success(scenes.size)
    }

    companion object {
        private const val TAG = "ExtractScenes"
    }
}
