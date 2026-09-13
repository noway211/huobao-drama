package com.huobao.zdrama.domain.usecase

import android.util.Log
import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character
import java.io.File

class GenerateCharacterImagesUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesImageRepository: AgnesImageRepository,
    private val mediaDownloadRepository: MediaDownloadRepository
) {
    suspend fun execute(
        projectId: Long,
        settings: AgnesSettings,
        forceRegenerate: Boolean = false
    ): Result<Int> {
        if (dramaRepository.getProject(projectId) == null) {
            return Result.failure(IllegalArgumentException("Project not found"))
        }

        val characters = dramaRepository.getCharacters(projectId)
        if (characters.isEmpty()) {
            return Result.failure(IllegalArgumentException("请先提取角色"))
        }

        Log.i(
            TAG,
            "generateCharacterImages start: project=$projectId characters=${characters.size} force=$forceRegenerate"
        )

        var completed = 0
        var generated = 0
        var firstError: Throwable? = null

        for (ch in characters) {
            // 用户确认覆盖时不跳过；否则保留已完成立绘。
            if (!forceRegenerate &&
                ch.imageStatus == AssetStatus.COMPLETED &&
                isExistingLocalFile(ch.imageLocalPath)
            ) {
                Log.i(TAG, "character ${ch.name} image already completed, skip")
                completed += 1
                continue
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
            if (imageResult.isSuccess) {
                val charImageUrl = imageResult.getOrThrow()
                val downloadResult = mediaDownloadRepository.downloadCharImage(projectId, ch.id, charImageUrl)
                if (downloadResult.isSuccess) {
                    completed += 1
                    generated += 1
                    dramaRepository.updateCharacterImage(
                        characterId = ch.id,
                        imageStatus = AssetStatus.COMPLETED,
                        imageUrl = charImageUrl,
                        imageLocalPath = downloadResult.getOrThrow(),
                        imageErrorMessage = null
                    )
                } else {
                    val throwable = downloadResult.exceptionOrNull() ?: IllegalStateException("角色图下载失败")
                    if (firstError == null) firstError = throwable
                    dramaRepository.updateCharacterImage(
                        characterId = ch.id,
                        imageStatus = AssetStatus.FAILED,
                        imageUrl = charImageUrl,
                        imageLocalPath = ch.imageLocalPath,
                        imageErrorMessage = throwable.message
                    )
                }
            } else {
                val throwable = imageResult.exceptionOrNull() ?: IllegalStateException("角色图生成失败")
                if (firstError == null) firstError = throwable
                dramaRepository.updateCharacterImage(
                    characterId = ch.id,
                    imageStatus = AssetStatus.FAILED,
                    imageUrl = ch.imageUrl,
                    imageLocalPath = ch.imageLocalPath,
                    imageErrorMessage = throwable.message
                )
            }
        }

        Log.i(TAG, "generateCharacterImages done: ok=$completed/${characters.size}")

        // 同步 2026-08-08 修复：全部成功（含已存在跳过）即视为成功
        if (completed == characters.size) {
            return Result.success(generated)
        }
        if (generated > 0) {
            return Result.success(generated)
        }
        return Result.failure(firstError ?: IllegalStateException("角色图生成失败"))
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }

    private fun buildPrompt(ch: Character): String {
        val description = ch.appearance.ifBlank { ch.description.ifBlank { "character portrait" } }
        return "${ch.name}, $description, high quality, front-facing portrait"
    }

    companion object {
        private const val TAG = "GenerateCharacterImages"
    }
}
