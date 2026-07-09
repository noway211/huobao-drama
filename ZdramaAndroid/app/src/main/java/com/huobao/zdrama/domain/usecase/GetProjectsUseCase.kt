package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.DramaProject

class GetProjectsUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun execute(): List<DramaProject> {
        return dramaRepository.getProjects()
    }
}
