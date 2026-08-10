package com.huobao.zdrama.domain.usecase

import android.util.Log
import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character
import java.io.File

class GenerateSingleCharacterImageUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesImageRepository: AgnesImageRepository,
    private val mediaDownloadRepository: MediaDownloadRepository
) {
    suspend fun execute(projectId: Long, characterId: Long, settings: AgnesSettings): Result<String> {
        val characters = dramaRepository.getCharacters(projectId)
        val ch = characters.firstOrNull { it.id == characterId }
            ?: return Result.failure(IllegalArgumentException("角色不存在"))

        if (ch.imageStatus == AssetStatus.COMPLETED && isExistingLocalFile(ch.imageLocalPath)) {
            Log.i(TAG, "character ${ch.name} image already completed, skip")
            return Result.success(ch.imageLocalPath ?: "")
        }

        dramaRepository.updateCharacterImage(
            characterId = ch.id,
            imageStatus = AssetStatus.PROCESSING,
            imageUrl = ch.imageUrl,
            imageLocalPath = ch.imageLocalPath,
            imageErrorMessage = null
        )

        val prompt = buildPrompt(ch)
        val imageResult = agnesImageRepository.generateImageForCharacter(settings, prompt)
        return if (imageResult.isSuccess) {
            val charImageUrl = imageResult.getOrThrow()
            val downloadResult = mediaDownloadRepository.downloadCharImage(projectId, ch.id, charImageUrl)
            if (downloadResult.isSuccess) {
                val localPath = downloadResult.getOrThrow()
                dramaRepository.updateCharacterImage(
                    characterId = ch.id,
                    imageStatus = AssetStatus.COMPLETED,
                    imageUrl = charImageUrl,
                    imageLocalPath = localPath,
                    imageErrorMessage = null
                )
                Result.success(localPath)
            } else {
                val error = downloadResult.exceptionOrNull()?.message ?: "角色图下载失败"
                dramaRepository.updateCharacterImage(
                    characterId = ch.id,
                    imageStatus = AssetStatus.FAILED,
                    imageUrl = charImageUrl,
                    imageLocalPath = ch.imageLocalPath,
                    imageErrorMessage = error
                )
                Result.failure(IllegalStateException(error))
            }
        } else {
            val error = imageResult.exceptionOrNull()?.message ?: "角色图生成失败"
            dramaRepository.updateCharacterImage(
                characterId = ch.id,
                imageStatus = AssetStatus.FAILED,
                imageUrl = ch.imageUrl,
                imageLocalPath = ch.imageLocalPath,
                imageErrorMessage = error
            )
            Result.failure(IllegalStateException(error))
        }
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }

    private fun buildPrompt(ch: Character): String {
        val description = ch.appearance.ifBlank { ch.description.ifBlank { "character portrait" } }
        return "${ch.name}, $description, high quality, front-facing portrait"
    }

    companion object {
        private const val TAG = "GenerateSingleCharImage"
    }
}
