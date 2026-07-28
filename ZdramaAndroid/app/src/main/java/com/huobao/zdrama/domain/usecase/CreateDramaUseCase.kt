package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.CreateDramaInput
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus

class CreateDramaUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun execute(input: CreateDramaInput): Long {
        val now = System.currentTimeMillis()
        val project = DramaProject(
            id = 0L,
            title = input.title,
            prompt = input.prompt,
            style = input.style,
            targetAudience = input.targetAudience,
            aspectRatio = input.aspectRatio,
            shotCount = input.shotCount,
            shotDurationSeconds = input.shotDurationSeconds,
            status = ProjectStatus.DRAFT,
            currentStage = GenerationStage.NONE,
            errorMessage = null,
            generatedScript = null,
            finalVideoStatus = AssetStatus.PENDING,
            finalVideoLocalPath = null,
            finalVideoErrorMessage = null,
            createdAt = now,
            updatedAt = now
        )
        val projectId = dramaRepository.createProject(project)
        // Auto-create episode 1 with the prompt as raw content
        dramaRepository.createEpisodeForProject(
            projectId = projectId,
            title = input.title,
            content = input.prompt
        )
        return projectId
    }
}
