package com.huobao.zdrama.domain.usecase

class RetryStoryboardUseCase {
    suspend fun execute(storyboardId: Long): Result<Unit> {
        return Result.success(Unit)
    }
}
