package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository

class UpdateCharacterAppearanceUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun updateAppearance(characterId: Long, appearance: String): Boolean {
        return dramaRepository.updateCharacterAppearance(characterId, appearance)
    }
}
