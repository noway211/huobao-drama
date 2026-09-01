package com.huobao.zdrama.data.repository

import android.content.Context
import android.util.Log
import com.huobao.zdrama.data.local.CharacterLocalDataSource
import com.huobao.zdrama.data.local.EpisodeLocalDataSource
import com.huobao.zdrama.data.local.ProjectLocalDataSource
import com.huobao.zdrama.data.local.StoryboardLocalDataSource
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.Episode
import com.huobao.zdrama.domain.model.EpisodeStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DramaRepository(context: Context) {
    private val projectLocalDataSource = ProjectLocalDataSource(context)
    private val storyboardLocalDataSource = StoryboardLocalDataSource(context)
    private val episodeLocalDataSource = EpisodeLocalDataSource(context)
    private val characterLocalDataSource = CharacterLocalDataSource(context)
    private val mediaDownloadRepository = MediaDownloadRepository(context)

    suspend fun createProject(project: DramaProject): Long = withContext(Dispatchers.IO) {
        projectLocalDataSource.insertProject(project)
    }

    suspend fun getProjects(): List<DramaProject> = withContext(Dispatchers.IO) {
        projectLocalDataSource.getProjects()
    }

    suspend fun getProject(projectId: Long): DramaProject? = withContext(Dispatchers.IO) {
        projectLocalDataSource.getProject(projectId)
    }

    suspend fun updateProjectTextResult(
        projectId: Long,
        status: ProjectStatus,
        currentStage: GenerationStage,
        generatedScript: String?,
        errorMessage: String?
    ): Boolean = withContext(Dispatchers.IO) {
        projectLocalDataSource.updateProjectTextResult(
            projectId = projectId,
            status = status,
            currentStage = currentStage,
            generatedScript = generatedScript,
            errorMessage = errorMessage
        ) > 0
    }

    suspend fun updateProjectFinalVideo(
        projectId: Long,
        status: ProjectStatus,
        currentStage: GenerationStage,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?,
        errorMessage: String?
    ): Boolean = withContext(Dispatchers.IO) {
        projectLocalDataSource.updateProjectFinalVideo(
            projectId = projectId,
            status = status,
            currentStage = currentStage,
            finalVideoStatus = finalVideoStatus,
            finalVideoLocalPath = finalVideoLocalPath,
            finalVideoErrorMessage = finalVideoErrorMessage,
            errorMessage = errorMessage
        ) > 0
    }

    /** 替换某集的全部分镜（先删后插）。 */
    suspend fun replaceStoryboards(projectId: Long, episodeId: Long, shots: List<StoryboardShot>) = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.replaceStoryboards(projectId, episodeId, shots)
    }

    suspend fun getStoryboards(projectId: Long): List<StoryboardShot> = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.getStoryboards(projectId)
    }

    /** 多集支持：查询某集的全部分镜。 */
    suspend fun getStoryboards(projectId: Long, episodeId: Long): List<StoryboardShot> = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.getStoryboards(projectId, episodeId)
    }

    suspend fun updateShotImage(
        shotId: Long,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ): Boolean = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.updateShotImage(
            shotId = shotId,
            imageStatus = imageStatus,
            imageUrl = imageUrl,
            imageLocalPath = imageLocalPath,
            imageErrorMessage = imageErrorMessage
        ) > 0
    }

    suspend fun updateShotVideo(
        shotId: Long,
        videoStatus: AssetStatus,
        videoTaskId: String?,
        videoUrl: String?,
        videoLocalPath: String?,
        videoErrorMessage: String?
    ): Boolean = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.updateShotVideo(
            shotId = shotId,
            videoStatus = videoStatus,
            videoTaskId = videoTaskId,
            videoUrl = videoUrl,
            videoLocalPath = videoLocalPath,
            videoErrorMessage = videoErrorMessage
        ) > 0
    }

    suspend fun updateShotImagePrompt(shotId: Long, newPrompt: String): Boolean = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.updateShotImagePrompt(shotId, newPrompt) > 0
    }

    suspend fun updateShotVideoPrompt(shotId: Long, newPrompt: String): Boolean = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.updateShotVideoPrompt(shotId, newPrompt) > 0
    }

    /** 更新分镜的角色绑定（JSON：数字 ID 数组或名字数组；空绑定传 "" 或 null）。 */
    suspend fun updateShotCharacterIds(shotId: Long, characterIds: String?): Boolean = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.updateShotCharacterIds(shotId, characterIds) > 0
    }

    // --- Episode methods ---

    suspend fun getEpisodeForProject(projectId: Long): Episode? = withContext(Dispatchers.IO) {
        episodeLocalDataSource.getEpisodeForProject(projectId)
    }

    suspend fun getEpisodes(projectId: Long): List<Episode> = withContext(Dispatchers.IO) {
        episodeLocalDataSource.getEpisodes(projectId)
    }

    /** 历史数据修复：episode_id 为 NULL 的存量分镜回填到所属项目第一集。 */
    suspend fun backfillStoryboardEpisodeIds() = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.backfillEpisodeIds()
    }

    suspend fun getEpisodeById(episodeId: Long): Episode? = withContext(Dispatchers.IO) {
        episodeLocalDataSource.getEpisodeById(episodeId)
    }

    /** 新建剧集：集号取当前最大 +1（项目首个为第 1 集），返回新集的 id。 */
    suspend fun createEpisodeForProject(projectId: Long, title: String, content: String?): Long = withContext(Dispatchers.IO) {
        val nextNumber = (episodeLocalDataSource.getEpisodes(projectId).maxOfOrNull { it.episodeNumber } ?: 0) + 1
        val now = System.currentTimeMillis()
        episodeLocalDataSource.insertEpisode(Episode(
            id = 0L,
            projectId = projectId,
            episodeNumber = nextNumber,
            title = title,
            content = content,
            scriptContent = null,
            status = EpisodeStatus.DRAFT,
            createdAt = now,
            updatedAt = now
        ))
    }

    /** 删除单集：级联删除该集分镜、成片与本地媒体目录，再删集记录。 */
    suspend fun deleteEpisode(episodeId: Long): Boolean = withContext(Dispatchers.IO) {
        val episode = episodeLocalDataSource.getEpisodeById(episodeId)
            ?: return@withContext false
        storyboardLocalDataSource.deleteStoryboardsForEpisode(episode.projectId, episodeId)
        unlinkIfExists(episode.finalVideoLocalPath, "episode final video #$episodeId")
        val dbOk = episodeLocalDataSource.deleteEpisode(episodeId) > 0
        // 清理该集媒体目录（分镜图片/视频存在 generated/<projectId>/ 下按 shot 命名，由 deleteProject 统一清理；这里只删成片目录）
        episode.finalVideoLocalPath?.takeIf { it.isNotBlank() }?.let { path ->
            runCatching { File(path).parentFile?.takeIf { it.exists() }?.deleteRecursively() }
                .onFailure { Log.w(TAG, "delete episode dir failed for #$episodeId: ${it.message}") }
        }
        dbOk
    }

    /** 软删除某集成片：DB 清状态 + 删本地文件。 */
    suspend fun deleteEpisodeFinalVideo(episodeId: Long): DeleteResult = withContext(Dispatchers.IO) {
        val episode = episodeLocalDataSource.getEpisodeById(episodeId)
            ?: return@withContext DeleteResult(dbUpdated = false, fileDeleted = false)
        val fileDeleted = unlinkIfExists(episode.finalVideoLocalPath, "episode final video #$episodeId")
        val dbOk = episodeLocalDataSource.updateEpisodeFinalVideo(episodeId, AssetStatus.PENDING, null, null) > 0
        DeleteResult(dbUpdated = dbOk, fileDeleted = fileDeleted)
    }

    /** 每集独立成片的状态写入（多集支持后的成片落库路径）。 */
    suspend fun updateEpisodeFinalVideo(
        episodeId: Long,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?
    ): Boolean = withContext(Dispatchers.IO) {
        episodeLocalDataSource.updateEpisodeFinalVideo(
            episodeId = episodeId,
            finalVideoStatus = finalVideoStatus,
            finalVideoLocalPath = finalVideoLocalPath,
            finalVideoErrorMessage = finalVideoErrorMessage
        ) > 0
    }

    suspend fun updateEpisodeScriptContent(
        episodeId: Long,
        scriptContent: String?,
        status: EpisodeStatus
    ): Boolean = withContext(Dispatchers.IO) {
        episodeLocalDataSource.updateEpisodeScriptContent(episodeId, scriptContent, status) > 0
    }

    suspend fun updateEpisodeContent(episodeId: Long, content: String?): Boolean = withContext(Dispatchers.IO) {
        episodeLocalDataSource.updateEpisodeContent(episodeId, content) > 0
    }

    suspend fun deleteProject(projectId: Long): Boolean = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.deleteStoryboards(projectId)
        characterLocalDataSource.deleteCharactersForProject(projectId)
        episodeLocalDataSource.deleteEpisodesForProject(projectId)
        val projectDeleted = projectLocalDataSource.deleteProject(projectId) > 0
        val mediaDeleted = mediaDownloadRepository.deleteGeneratedMedia(projectId)
        projectDeleted && mediaDeleted
    }

    // --- Character methods ---

    suspend fun replaceCharacters(projectId: Long, characters: List<Character>) = withContext(Dispatchers.IO) {
        characterLocalDataSource.replaceCharacters(projectId, characters)
    }

    suspend fun getCharacters(projectId: Long): List<Character> = withContext(Dispatchers.IO) {
        characterLocalDataSource.getCharacters(projectId)
    }

    suspend fun updateCharacterImage(
        characterId: Long,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ): Boolean = withContext(Dispatchers.IO) {
        characterLocalDataSource.updateCharacterImage(
            characterId = characterId,
            imageStatus = imageStatus,
            imageUrl = imageUrl,
            imageLocalPath = imageLocalPath,
            imageErrorMessage = imageErrorMessage
        ) > 0
    }

    suspend fun updateCharacterAppearance(characterId: Long, appearance: String): Boolean = withContext(Dispatchers.IO) {
        characterLocalDataSource.updateCharacterAppearance(characterId, appearance) > 0
    }

    // ────────────── 软删除（DB status → PENDING + 清字段 + 删本地文件） ──────────────
    //
    // 与鸿蒙端 `viewer-delete-assets` (commit 0dfde93) 行为一致：DB 软删除必做，本地文件容错
    // （File.delete() 失败不抛，只 warn），单条 / 全量两种粒度。

    /** 软删除单张分镜图片：DB 软删除 + 删除本地文件。返回 (DB ok, 本地文件是否被删)。 */
    suspend fun deleteShotImage(shotId: Long): DeleteResult = withContext(Dispatchers.IO) {
        val shot = getShotByIdFallback(shotId)
            ?: return@withContext DeleteResult(dbUpdated = false, fileDeleted = false)
        val fileDeleted = unlinkIfExists(shot.imageLocalPath, "shot image #$shotId")
        val dbOk = updateShotImage(shotId, AssetStatus.PENDING, null, null, null)
        DeleteResult(dbUpdated = dbOk, fileDeleted = fileDeleted)
    }

    /** 软删除单条分镜视频：DB 软删除 + 删除本地文件。 */
    suspend fun deleteShotVideo(shotId: Long): DeleteResult = withContext(Dispatchers.IO) {
        val shot = getShotByIdFallback(shotId)
            ?: return@withContext DeleteResult(dbUpdated = false, fileDeleted = false)
        val fileDeleted = unlinkIfExists(shot.videoLocalPath, "shot video #$shotId")
        val dbOk = updateShotVideo(shotId, AssetStatus.PENDING, null, null, null, null)
        DeleteResult(dbUpdated = dbOk, fileDeleted = fileDeleted)
    }

    /** 软删除单张角色立绘：DB 软删除 + 删除本地文件。 */
    suspend fun deleteCharacterImage(characterId: Long): DeleteResult = withContext(Dispatchers.IO) {
        val character = characterLocalDataSource.getCharacter(characterId)
            ?: return@withContext DeleteResult(dbUpdated = false, fileDeleted = false)
        val fileDeleted = unlinkIfExists(character.imageLocalPath, "character image #$characterId")
        val dbOk = updateCharacterImage(characterId, AssetStatus.PENDING, null, null, null)
        DeleteResult(dbUpdated = dbOk, fileDeleted = fileDeleted)
    }

    /** 软删除项目成片：DB 软删除（保留 status / currentStage）+ 删除本地文件。 */
    suspend fun deleteProjectFinalVideo(projectId: Long): DeleteResult = withContext(Dispatchers.IO) {
        val project = getProject(projectId)
            ?: return@withContext DeleteResult(dbUpdated = false, fileDeleted = false)
        val fileDeleted = unlinkIfExists(project.finalVideoLocalPath, "final video #$projectId")
        val dbOk = updateProjectFinalVideo(
            projectId = projectId,
            status = project.status,
            currentStage = project.currentStage,
            finalVideoStatus = AssetStatus.PENDING,
            finalVideoLocalPath = null,
            finalVideoErrorMessage = null,
            errorMessage = project.errorMessage
        )
        DeleteResult(dbUpdated = dbOk, fileDeleted = fileDeleted)
    }

    /** 批量软删除某集所有分镜图片。返回成功条数。 */
    suspend fun deleteAllStoryboardImages(projectId: Long, episodeId: Long): Int = withContext(Dispatchers.IO) {
        var count = 0
        getStoryboards(projectId, episodeId).forEach { shot ->
            if (shot.imageLocalPath.isNullOrBlank() && shot.imageUrl.isNullOrBlank()) return@forEach
            if (deleteShotImage(shot.id).dbUpdated) count++
        }
        count
    }

    /** 批量软删除某集所有分镜视频。返回成功条数。 */
    suspend fun deleteAllStoryboardVideos(projectId: Long, episodeId: Long): Int = withContext(Dispatchers.IO) {
        var count = 0
        getStoryboards(projectId, episodeId).forEach { shot ->
            if (shot.videoLocalPath.isNullOrBlank() && shot.videoUrl.isNullOrBlank()) return@forEach
            if (deleteShotVideo(shot.id).dbUpdated) count++
        }
        count
    }

    /**
     * 单 shot 查询：getStoryboards 只按 projectId 查，所以用最小反范式——遍历
     * 当前缓存的所有 storyboard 项目。生产项目大后可换成 dedicated 单 shot DAO。
     * 当前规模 (≤ 几十个分镜/项目) 可接受。
     */
    private suspend fun getShotByIdFallback(shotId: Long): StoryboardShot? = withContext(Dispatchers.IO) {
        // 反范式：扫描所有 project 的 storyboard 找 shotId 对应 shot。
        // 注意：实际项目数有限，避免引入额外 DAO。
        projectLocalDataSource.getProjects().firstNotNullOfOrNull { p ->
            storyboardLocalDataSource.getStoryboards(p.id).firstOrNull { it.id == shotId }
        }
    }

    /** 软删除工具：存在则删，失败只 warn 不抛。 */
    private fun unlinkIfExists(path: String?, tag: String): Boolean {
        if (path.isNullOrBlank()) return false
        return runCatching { File(path).takeIf { it.exists() }?.delete() ?: false }
            .onFailure { Log.w(TAG, "unlink failed for $tag ($path): ${it.message}") }
            .getOrDefault(false)
    }

    /** 软删除结果：DB 是否成功更新 + 本地文件是否被删除。 */
    data class DeleteResult(val dbUpdated: Boolean, val fileDeleted: Boolean)

    companion object {
        private const val TAG = "DramaRepository"
    }
}
