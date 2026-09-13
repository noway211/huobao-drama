package com.huobao.zdrama.domain.usecase

import android.util.Log
import com.google.gson.Gson
import com.huobao.zdrama.data.prompt.PromptDefaults
import com.huobao.zdrama.data.prompt.PromptResolver
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.remote.ChatResponseTextExtractor
import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character
import java.io.File

class ExtractCharactersUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesTextRepository: AgnesTextRepository
) {
    suspend fun execute(projectId: Long, episodeId: Long, settings: AgnesSettings): Result<Int> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))

        // 多集支持：只从当前集脚本提取，禁止回退 project.generatedScript（那通常是别的集）。
        // 角色仍挂项目级（对齐 backend drama 级 characters + save_dedup_characters）。
        val episode = dramaRepository.getEpisodeById(episodeId)
            ?: return Result.failure(IllegalArgumentException("Episode not found"))
        val script = episode.scriptContent
        if (script.isNullOrBlank()) {
            return Result.failure(IllegalArgumentException("请先为本集创作或改写脚本"))
        }

        // 读取已有角色，传给 LLM 做去重参考
        val existingChars = dramaRepository.getCharacters(projectId)
        val existingHint = if (existingChars.isNotEmpty()) {
            val names = existingChars.joinToString("、") { it.name }
            "\n\n项目中已存在角色：$names。若剧本中同名角色已存在，请合并更新其信息；若为新角色则创建。"
        } else {
            ""
        }

        val systemPrompt = PromptResolver.resolve(
            settings.customCharacterExtractPrompt,
            PromptDefaults.CHARACTER_EXTRACT_PROMPT
        )

        val userPrompt = """请从以下剧本中提取所有角色信息，返回 JSON 数组。
每个条目包含：name（角色名）、role（主角/配角/龙套）、description（角色描述）、appearance（外貌特征，用于生成角色立绘）、personality（性格特征）。
${if (existingChars.isNotEmpty()) "若角色已存在（名字匹配），请在条目中加 existing_id 字段标记已有角色的 id。" else ""}
只返回 JSON 数组。

剧本：
$script$existingHint"""

        val rawResult = agnesTextRepository.postChat(
            settings = settings,
            messages = listOf(
                ChatMessage(role = "system", content = systemPrompt),
                ChatMessage(role = "user", content = userPrompt)
            ),
            temperature = 0.3,
            maxTokens = 4000
        )
        if (rawResult.isFailure) {
            val err = rawResult.exceptionOrNull()?.message ?: "角色提取请求失败"
            return Result.failure(IllegalStateException(err))
        }

        val rawJson = rawResult.getOrThrow()
        val parsedElement = runCatching { Gson().fromJson(rawJson, com.google.gson.JsonElement::class.java) }
            .getOrNull() ?: return Result.failure(IllegalStateException("无法解析响应 JSON"))
        val contentText = ChatResponseTextExtractor.extractFinalContent(parsedElement)
        if (contentText.isBlank()) {
            return Result.failure(IllegalStateException("Agnes 未返回角色信息"))
        }

        // 解析 JSON 数组
        var jsonStr = contentText.trim()
        if (!jsonStr.startsWith("[")) {
            val start = jsonStr.indexOf('[')
            val end = jsonStr.lastIndexOf(']')
            if (start >= 0 && end > start) {
                jsonStr = jsonStr.substring(start, end + 1)
            }
        }
        val items: List<Map<String, Any?>> = runCatching {
            val list = Gson().fromJson(jsonStr, List::class.java)
            list.filterIsInstance<Map<String, Any?>>()
        }.getOrElse {
            return Result.failure(IllegalStateException("无法解析角色提取结果"))
        }
        if (items.isEmpty()) {
            return Result.failure(IllegalStateException("未从剧本中提取到角色"))
        }

        val now = System.currentTimeMillis()
        val nameToExisting = existingChars.associateBy { it.name }
        Log.i(
            TAG,
            "extractCharacters start: project=$projectId episode=${episode.id} " +
                "existing=${existingChars.size} [${existingChars.joinToString { it.name }}] parsed=${items.size}"
        )

        var merged = 0
        var inserted = 0
        val characters: List<Character> = items.mapNotNull { item ->
            val name = (item["name"] as? String)?.trim().orEmpty()
            if (name.isEmpty()) return@mapNotNull null
            val role = (item["role"] as? String).orEmpty()
            val description = (item["description"] as? String).orEmpty()
            val appearance = (item["appearance"] as? String).orEmpty()
            val personality = (item["personality"] as? String).orEmpty()
            val existing = nameToExisting[name]
            if (existing != null) {
                merged += 1
                Log.i(TAG, "merge character name=$name id=${existing.id} keepImage=${existing.imageStatus}")
            } else {
                inserted += 1
                Log.i(TAG, "insert character name=$name")
            }
            Character(
                id = existing?.id ?: 0L,
                projectId = projectId,
                episodeId = episode.id,
                name = name,
                role = role.ifBlank { existing?.role.orEmpty() },
                description = description.ifBlank { existing?.description.orEmpty() },
                appearance = appearance.ifBlank { existing?.appearance.orEmpty() },
                personality = personality.ifBlank { existing?.personality.orEmpty() },
                imageStatus = existing?.imageStatus ?: AssetStatus.PENDING,
                imageUrl = existing?.imageUrl,
                imageLocalPath = existing?.imageLocalPath,
                imageErrorMessage = existing?.imageErrorMessage,
                createdAt = existing?.createdAt ?: now,
                updatedAt = now
            )
        }
        if (characters.isEmpty()) {
            return Result.failure(IllegalStateException("未从剧本中提取到角色"))
        }

        // 增量写入：同名 UPDATE 保留 id/立绘；新角色 INSERT；本集未出现的老角色不删。
        dramaRepository.upsertCharacters(projectId, characters)
        Log.i(
            TAG,
            "extractCharacters done: project=$projectId episode=${episode.id} " +
                "upserted=${characters.size} merged=$merged inserted=$inserted"
        )
        return Result.success(characters.size)
    }

    companion object {
        private const val TAG = "ExtractCharacters"
    }
}
