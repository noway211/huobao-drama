package com.huobao.zdrama.domain.usecase

class GenerateImagesUseCase {
    suspend fun execute(projectId: Long): Result<Unit> {
        return Result.success(Unit)
    }
}
