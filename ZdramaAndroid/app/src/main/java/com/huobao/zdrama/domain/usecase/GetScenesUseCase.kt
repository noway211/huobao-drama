package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.Scene

class GetScenesUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun execute(projectId: Long): List<Scene> {
        return dramaRepository.getScenes(projectId)
    }
}
