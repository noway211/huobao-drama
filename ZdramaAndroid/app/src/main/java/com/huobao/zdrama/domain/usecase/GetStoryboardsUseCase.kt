package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.StoryboardShot

class GetStoryboardsUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun execute(projectId: Long): List<StoryboardShot> {
        return dramaRepository.getStoryboards(projectId)
    }
}
