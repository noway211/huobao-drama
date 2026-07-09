package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.AgnesConnectionRepository
import com.huobao.zdrama.data.settings.AgnesSettings

class TestAgnesConnectionUseCase(
    private val repository: AgnesConnectionRepository = AgnesConnectionRepository()
) {
    suspend fun execute(settings: AgnesSettings): Result<Unit> {
        return repository.testTextModel(settings)
    }
}
