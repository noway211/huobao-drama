package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.AgnesStoryboardRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot

class GenerateStoryboardsUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesStoryboardRepository: AgnesStoryboardRepository
) {
    suspend fun execute(projectId: Long, episodeId: Long, settings: AgnesSettings): Result<List<StoryboardShot>> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))

        // 只使用当前集脚本，禁止回退 project.generatedScript（那通常是别的集）。
        val episode = dramaRepository.getEpisodeById(episodeId)
            ?: return Result.failure(IllegalArgumentException("Episode not found"))
        val script = episode.scriptContent
        if (script.isNullOrBlank()) {
            return Result.failure(IllegalArgumentException("请先为本集创作或改写脚本"))
        }

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.STORYBOARD,
            generatedScript = project.generatedScript,
            errorMessage = null
        )

        val result = agnesStoryboardRepository.generateStoryboards(settings, project, script)
        result.onSuccess { shots ->
            dramaRepository.replaceStoryboards(projectId, episodeId, shots)
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.COMPLETED,
                currentStage = GenerationStage.STORYBOARD,
                generatedScript = project.generatedScript,
                errorMessage = null
            )
        }.onFailure { throwable ->
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.FAILED,
                currentStage = GenerationStage.STORYBOARD,
                generatedScript = project.generatedScript,
                errorMessage = throwable.message
            )
        }
        return result
    }
}
