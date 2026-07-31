package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository

class UpdateShotPromptUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun updateImagePrompt(shotId: Long, newPrompt: String): Boolean {
        return dramaRepository.updateShotImagePrompt(shotId, newPrompt)
    }

    suspend fun updateVideoPrompt(shotId: Long, newPrompt: String): Boolean {
        return dramaRepository.updateShotVideoPrompt(shotId, newPrompt)
    }
}