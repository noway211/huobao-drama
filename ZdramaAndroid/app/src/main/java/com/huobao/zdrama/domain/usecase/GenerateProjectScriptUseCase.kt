package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.EpisodeStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus

class GenerateProjectScriptUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesTextRepository: AgnesTextRepository
) {
    /**
     * 基于项目信息（标题/提示词/风格）为目标剧集生成剧本。
     * 结果写入 episode.scriptContent；project.generatedScript 同步镜像最新集脚本（兼容旧读取方）。
     */
    suspend fun execute(projectId: Long, episodeId: Long, settings: AgnesSettings): Result<String> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))
        val episode = dramaRepository.getEpisodeById(episodeId)
            ?: dramaRepository.getEpisodeForProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Episode not found"))

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.TEXT,
            generatedScript = project.generatedScript,
            errorMessage = null
        )

        val storyPrompt = episode.content?.takeIf { it.isNotBlank() } ?: project.prompt
        val result = agnesTextRepository.generateScript(settings, project, storyPrompt)
        result.onSuccess { script ->
            dramaRepository.updateEpisodeScriptContent(
                episodeId = episode.id,
                scriptContent = script,
                status = EpisodeStatus.COMPLETED
            )
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.COMPLETED,
                currentStage = GenerationStage.TEXT,
                generatedScript = script,
                errorMessage = null
            )
        }.onFailure { throwable ->
            dramaRepository.updateEpisodeScriptContent(
                episodeId = episode.id,
                scriptContent = episode.scriptContent,
                status = EpisodeStatus.FAILED
            )
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.FAILED,
                currentStage = GenerationStage.TEXT,
                generatedScript = episode.scriptContent ?: project.generatedScript,
                errorMessage = throwable.message
            )
        }
        return result
    }
}