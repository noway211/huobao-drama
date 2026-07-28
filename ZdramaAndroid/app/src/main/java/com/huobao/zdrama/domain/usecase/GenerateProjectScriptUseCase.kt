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
    suspend fun execute(projectId: Long, settings: AgnesSettings): Result<String> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.TEXT,
            generatedScript = project.generatedScript,
            errorMessage = null
        )

        val result = agnesTextRepository.generateScript(settings, project)
        result.onSuccess { script ->
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.COMPLETED,
                currentStage = GenerationStage.TEXT,
                generatedScript = script,
                errorMessage = null
            )
            // Sync to episode.scriptContent
            val episode = dramaRepository.getEpisodeForProject(projectId)
            if (episode != null) {
                dramaRepository.updateEpisodeScriptContent(
                    episodeId = episode.id,
                    scriptContent = script,
                    status = EpisodeStatus.COMPLETED
                )
            }
        }.onFailure { throwable ->
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.FAILED,
                currentStage = GenerationStage.TEXT,
                generatedScript = project.generatedScript,
                errorMessage = throwable.message
            )
        }
        return result
    }
}
