package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import java.io.File

class GenerateStoryboardImagesUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesImageRepository: AgnesImageRepository,
    private val mediaDownloadRepository: MediaDownloadRepository
) {
    suspend fun execute(projectId: Long, settings: AgnesSettings): Result<Int> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))
        val shots = dramaRepository.getStoryboards(projectId)
        if (shots.isEmpty()) {
            return Result.failure(IllegalArgumentException("Generate storyboards before images"))
        }

        // 自动修复触发内容审查的提示词（与 Harmony 端同步）
        patchSensitivePrompts(shots)

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.IMAGE,
            generatedScript = project.generatedScript,
            errorMessage = null
        )

        var completed = 0
        var generated = 0
        var firstError: Throwable? = null
        for (shot in shots) {
            if (shot.imageStatus == AssetStatus.COMPLETED && isExistingLocalFile(shot.imageLocalPath)) {
                completed += 1
                continue
            }

            dramaRepository.updateShotImage(
                shotId = shot.id,
                imageStatus = AssetStatus.PROCESSING,
                imageUrl = shot.imageUrl,
                imageLocalPath = shot.imageLocalPath,
                imageErrorMessage = null
            )

            val imageResult = agnesImageRepository.generateImage(settings, shot)
            if (imageResult.isSuccess) {
                val imageUrl = imageResult.getOrThrow()
                val downloadResult = mediaDownloadRepository.downloadToGeneratedMedia(
                    projectId = projectId,
                    shotId = shot.id,
                    url = imageUrl,
                    mediaType = MediaDownloadRepository.MediaType.IMAGE
                )
                if (downloadResult.isSuccess) {
                    completed += 1
                    generated += 1
                    dramaRepository.updateShotImage(
                        shotId = shot.id,
                        imageStatus = AssetStatus.COMPLETED,
                        imageUrl = imageUrl,
                        imageLocalPath = downloadResult.getOrThrow(),
                        imageErrorMessage = null
                    )
                } else {
                    val throwable = downloadResult.exceptionOrNull() ?: IllegalStateException("Image download failed")
                    if (firstError == null) firstError = throwable
                    dramaRepository.updateShotImage(
                        shotId = shot.id,
                        imageStatus = AssetStatus.FAILED,
                        imageUrl = imageUrl,
                        imageLocalPath = shot.imageLocalPath,
                        imageErrorMessage = throwable.message
                    )
                }
            } else {
                val throwable = imageResult.exceptionOrNull() ?: IllegalStateException("Image generation failed")
                if (firstError == null) firstError = throwable
                dramaRepository.updateShotImage(
                    shotId = shot.id,
                    imageStatus = AssetStatus.FAILED,
                    imageUrl = shot.imageUrl,
                    imageLocalPath = shot.imageLocalPath,
                    imageErrorMessage = throwable.message
                )
            }
        }

        val finalStatus = if (completed == shots.size) ProjectStatus.COMPLETED else ProjectStatus.FAILED
        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = finalStatus,
            currentStage = GenerationStage.IMAGE,
            generatedScript = project.generatedScript,
            errorMessage = firstError?.message
        )

        return if (completed > 0) Result.success(generated) else Result.failure(
            firstError ?: IllegalStateException("Image generation failed")
        )
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }

    /** 自动替换触发内容审查的敏感词，对齐 Harmony 端 patchSensitivePrompts。 */
    private suspend fun patchSensitivePrompts(shots: List<StoryboardShot>) {
        for (shot in shots) {
            val old1 = "走廊尽头传来脚步声，老师快步走来，身后跟着校警，众人瞬间安静，学校走廊场景，写实风格"
            if (shot.imagePrompt == old1) {
                dramaRepository.updateShotImagePrompt(shot.id,
                    "走廊尽头传来脚步声，老师快步走来，严厉地扫视全场，霸凌者心虚地低下头，众人不敢出声，学校走廊场景，写实风格")
            }
            val old2 = "校警将霸凌者带离走廊"
            if (shot.imagePrompt.contains(old2)) {
                dramaRepository.updateShotImagePrompt(shot.id,
                    shot.imagePrompt.replace(old2, "老师带着霸凌者离开走廊"))
            }
            if (shot.videoPrompt.contains(old2)) {
                dramaRepository.updateShotVideoPrompt(shot.id,
                    shot.videoPrompt.replace(old2, "老师带着霸凌者离开走廊"))
            }
        }
    }
}
