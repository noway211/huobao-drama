package com.huobao.zdrama.data.repository

import android.content.Context
import com.huobao.zdrama.data.local.EpisodeLocalDataSource
import com.huobao.zdrama.data.local.ProjectLocalDataSource
import com.huobao.zdrama.data.local.StoryboardLocalDataSource
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.Episode
import com.huobao.zdrama.domain.model.EpisodeStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DramaRepository(context: Context) {
    private val projectLocalDataSource = ProjectLocalDataSource(context)
    private val storyboardLocalDataSource = StoryboardLocalDataSource(context)
    private val episodeLocalDataSource = EpisodeLocalDataSource(context)
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

    suspend fun replaceStoryboards(projectId: Long, shots: List<StoryboardShot>) = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.replaceStoryboards(projectId, shots)
    }

    suspend fun getStoryboards(projectId: Long): List<StoryboardShot> = withContext(Dispatchers.IO) {
        storyboardLocalDataSource.getStoryboards(projectId)
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

    // --- Episode methods ---

    suspend fun getEpisodeForProject(projectId: Long): Episode? = withContext(Dispatchers.IO) {
        episodeLocalDataSource.getEpisodeForProject(projectId)
    }

    suspend fun createEpisodeForProject(projectId: Long, title: String, content: String?): Long = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        episodeLocalDataSource.insertEpisode(Episode(
            id = 0L,
            projectId = projectId,
            episodeNumber = 1,
            title = title,
            content = content,
            scriptContent = null,
            status = EpisodeStatus.DRAFT,
            createdAt = now,
            updatedAt = now
        ))
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
        episodeLocalDataSource.deleteEpisodesForProject(projectId)
        val projectDeleted = projectLocalDataSource.deleteProject(projectId) > 0
        val mediaDeleted = mediaDownloadRepository.deleteGeneratedMedia(projectId)
        projectDeleted && mediaDeleted
    }
}
