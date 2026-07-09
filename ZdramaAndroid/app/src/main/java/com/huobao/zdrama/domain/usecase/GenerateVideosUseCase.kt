package com.huobao.zdrama.domain.usecase

class GenerateVideosUseCase {
    suspend fun execute(projectId: Long): Result<Unit> {
        return Result.success(Unit)
    }
}
