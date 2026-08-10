package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.Character

class GetCharactersUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun execute(projectId: Long): List<Character> {
        return dramaRepository.getCharacters(projectId)
    }
}
