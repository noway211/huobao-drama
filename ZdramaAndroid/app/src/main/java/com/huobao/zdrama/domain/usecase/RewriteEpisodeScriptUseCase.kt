package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.EpisodeStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus

class RewriteEpisodeScriptUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesTextRepository: AgnesTextRepository
) {
    /**
     * Rewrites the episode's raw content into a formatted screenplay.
     * Reads from episode.content, writes result to episode.scriptContent.
     * Also syncs to project.generatedScript for backward compatibility.
     */
    suspend fun execute(projectId: Long, episodeId: Long, settings: AgnesSettings): Result<String> {
        val episode = dramaRepository.getEpisodeById(episodeId)
            ?: dramaRepository.getEpisodeForProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Episode not found for project"))
        val rawContent = episode.content
            ?: return Result.failure(IllegalArgumentException("Episode has no raw content to rewrite"))
        if (rawContent.isBlank()) {
            return Result.failure(IllegalArgumentException("Episode raw content is empty"))
        }

        // Mark episode as rewriting
        dramaRepository.updateEpisodeScriptContent(
            episodeId = episode.id,
            scriptContent = episode.scriptContent,
            status = EpisodeStatus.REWRITING
        )
        // Mark project as processing
        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.TEXT,
            generatedScript = episode.scriptContent,
            errorMessage = null
        )

        val result = agnesTextRepository.rewriteScript(settings, rawContent)

        result.onSuccess { scriptContent ->
            dramaRepository.updateEpisodeScriptContent(
                episodeId = episode.id,
                scriptContent = scriptContent,
                status = EpisodeStatus.COMPLETED
            )
            // Dual-write to project.generatedScript for backward compatibility
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.COMPLETED,
                currentStage = GenerationStage.TEXT,
                generatedScript = scriptContent,
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
                generatedScript = episode.scriptContent,
                errorMessage = throwable.message
            )
        }
        return result
    }
}