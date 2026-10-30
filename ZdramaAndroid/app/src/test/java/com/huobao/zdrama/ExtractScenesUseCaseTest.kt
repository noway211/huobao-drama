package com.huobao.zdrama

import com.huobao.zdrama.data.local.SceneDeduper
import com.huobao.zdrama.data.local.SceneLocalDataSource
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.Episode
import com.huobao.zdrama.domain.model.EpisodeStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.Scene
import com.huobao.zdrama.domain.usecase.ExtractScenesUseCase
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ExtractScenesUseCaseTest {
    @Test
    fun sameLocationAndTimeUpdatesInsteadOfInserting() {
        val existing = scene(id = 7L, location = "客厅", time = "夜晚", atmosphere = "旧氛围", prompt = "old prompt")

        val merged = SceneDeduper.upsert(
            existing = listOf(existing),
            incoming = listOf(scene(id = 0L, location = "客厅", time = "夜晚", atmosphere = "灯火昏暗", prompt = "dim living room, no people")),
            now = 20L
        )

        assertEquals(1, merged.size)
        assertEquals(7L, merged.single().id)
        assertEquals("灯火昏暗", merged.single().atmosphere)
        assertEquals("dim living room, no people", merged.single().prompt)
    }

    @Test
    fun sameLocationDifferentTimeInsertsAnotherRow() {
        val existing = scene(id = 7L, location = "客厅", time = "夜晚", atmosphere = "旧氛围", prompt = "old prompt")

        val merged = SceneDeduper.upsert(
            existing = listOf(existing),
            incoming = listOf(scene(id = 0L, location = "客厅", time = "白天", atmosphere = "阳光", prompt = "sunny living room, no people")),
            now = 20L
        )

        assertEquals(2, merged.size)
        assertEquals(listOf("夜晚", "白天"), merged.map { it.time })
        assertEquals(8L, merged[1].id)
    }

    @Test
    fun blankScriptReturnsScriptError() = runBlocking {
        val error = useCase(script = "   ", response = "[]")
            .execute(1L, 1L, settings())
            .exceptionOrNull()

        assertEquals("请先为本集创作或改写脚本", error?.message)
    }

    @Test
    fun unparseableReplyReturnsParseError() = runBlocking {
        val error = useCase(script = "客厅里有人说话", response = """{"choices":[{"message":{"content":"不是 JSON"}}]}""")
            .execute(1L, 1L, settings())
            .exceptionOrNull()

        assertEquals("无法解析场景提取结果", error?.message)
    }

    @Test
    fun emptySceneListReturnsEmptyError() = runBlocking {
        val error = useCase(script = "没有具体场景", response = """{"choices":[{"message":{"content":"[]"}}]}""")
            .execute(1L, 1L, settings())
            .exceptionOrNull()

        assertEquals("未从剧本中提取到场景", error?.message)
    }

    @Test
    fun extractedScenesAreDedupedBeforeSaving() = runBlocking {
        val saved = mutableListOf<Scene>()
        val repository = repository(
            script = "客厅，夜晚",
            existing = listOf(scene(id = 3L, location = "客厅", time = "夜晚", atmosphere = "旧", prompt = "old")),
            saved = saved
        )
        val response = """{"choices":[{"message":{"content":"[{\"location\":\"客厅\",\"time\":\"夜晚\",\"atmosphere\":\"新氛围\",\"prompt\":\"new prompt\"},{\"location\":\"\",\"time\":\"白天\",\"atmosphere\":\"丢弃\",\"prompt\":\"drop\"}]"}}]}"""

        val result = ExtractScenesUseCase(repository, textRepository(response))
            .execute(1L, 1L, settings())

        assertTrue(result.isSuccess)
        assertEquals(1, result.getOrNull())
        assertEquals(1, saved.size)
        assertEquals(3L, saved.single().id)
        assertEquals("新氛围", saved.single().atmosphere)
    }

    private fun useCase(script: String, response: String): ExtractScenesUseCase {
        return ExtractScenesUseCase(repository(script, emptyList(), mutableListOf()), textRepository(response))
    }

    private fun textRepository(response: String): AgnesTextRepository {
        return object : AgnesTextRepository() {
            override suspend fun postChat(
                settings: AgnesSettings,
                messages: List<ChatMessage>,
                temperature: Double,
                maxTokens: Int
            ): Result<String> = Result.success(response)
        }
    }

    private fun repository(script: String, existing: List<Scene>, saved: MutableList<Scene>): DramaRepository {
        val context = object : android.content.ContextWrapper(null) {}
        val scenes = object : SceneLocalDataSource(null) {
            override fun getScenes(projectId: Long): List<Scene> = existing
            override fun upsertScenes(projectId: Long, scenes: List<Scene>) {
                saved.clear()
                saved.addAll(SceneDeduper.upsert(existing, scenes, 20L))
            }
        }
        return object : DramaRepository(context, scenes) {
            override suspend fun getProject(projectId: Long): DramaProject? = project()
            override suspend fun getEpisodeById(episodeId: Long): Episode? = episode(script)
        }
    }

    private fun scene(
        id: Long,
        location: String,
        time: String,
        atmosphere: String,
        prompt: String
    ): Scene {
        return Scene(
            id = id,
            projectId = 1L,
            episodeId = 1L,
            location = location,
            time = time,
            atmosphere = atmosphere,
            prompt = prompt,
            createdAt = 1L,
            updatedAt = 1L
        )
    }

    private fun episode(script: String): Episode {
        return Episode(
            id = 1L,
            projectId = 1L,
            episodeNumber = 1,
            title = "第一集",
            content = "原文",
            scriptContent = script,
            status = EpisodeStatus.COMPLETED,
            createdAt = 1L,
            updatedAt = 1L
        )
    }

    private fun project(): DramaProject {
        return DramaProject(
            id = 1L,
            title = "测试短剧",
            prompt = "提示",
            style = "写实",
            targetAudience = "通用",
            aspectRatio = "9:16",
            shotCount = 3,
            shotDurationSeconds = 5,
            status = ProjectStatus.DRAFT,
            currentStage = GenerationStage.NONE,
            errorMessage = null,
            generatedScript = null,
            finalVideoStatus = AssetStatus.PENDING,
            finalVideoLocalPath = null,
            finalVideoErrorMessage = null,
            createdAt = 1L,
            updatedAt = 1L
        )
    }

    private fun settings(): AgnesSettings {
        return AgnesSettings(
            apiKey = "test-key",
            baseUrl = AgnesSettings.DEFAULT_BASE_URL,
            textModel = "test-model",
            imageModel = AgnesSettings.DEFAULT_IMAGE_MODEL,
            videoModel = AgnesSettings.DEFAULT_VIDEO_MODEL,
            requestTimeoutSeconds = AgnesSettings.DEFAULT_TIMEOUT_SECONDS
        )
    }
}
