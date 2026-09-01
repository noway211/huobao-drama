package com.huobao.zdrama.domain.usecase

import android.util.Base64
import com.huobao.zdrama.data.repository.AgnesVideoRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import java.io.File

class GenerateStoryboardVideosUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesVideoRepository: AgnesVideoRepository,
    private val mediaDownloadRepository: MediaDownloadRepository
) {
    suspend fun execute(projectId: Long, episodeId: Long, settings: AgnesSettings): Result<Int> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))
        val shots = dramaRepository.getStoryboards(projectId, episodeId)
        if (shots.isEmpty()) {
            return Result.failure(IllegalArgumentException("Generate storyboards before videos"))
        }

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.VIDEO,
            generatedScript = project.generatedScript,
            errorMessage = null
        )

        var completed = 0
        var generated = 0
        var firstError: Throwable? = null
        for (shot in shots) {
            if (shot.videoStatus == AssetStatus.COMPLETED && isExistingLocalFile(shot.videoLocalPath)) {
                completed += 1
                continue
            }

            dramaRepository.updateShotVideo(
                shotId = shot.id,
                videoStatus = AssetStatus.PROCESSING,
                videoTaskId = shot.videoTaskId,
                videoUrl = shot.videoUrl,
                videoLocalPath = shot.videoLocalPath,
                videoErrorMessage = null
            )

            val imageReference = shot.imageLocalPath
                ?.takeIf { isExistingLocalFile(it) }
                ?.let { localImagePathToDataUri(it) }
            val videoResult = agnesVideoRepository.generateVideo(settings, shot, imageReference)
            if (videoResult.isSuccess) {
                val generatedVideo = videoResult.getOrThrow()
                val downloadResult = mediaDownloadRepository.downloadToGeneratedMedia(
                    projectId = projectId,
                    shotId = shot.id,
                    url = generatedVideo.videoUrl,
                    mediaType = MediaDownloadRepository.MediaType.VIDEO
                )
                if (downloadResult.isSuccess) {
                    completed += 1
                    generated += 1
                    dramaRepository.updateShotVideo(
                        shotId = shot.id,
                        videoStatus = AssetStatus.COMPLETED,
                        videoTaskId = generatedVideo.taskId,
                        videoUrl = generatedVideo.videoUrl,
                        videoLocalPath = downloadResult.getOrThrow(),
                        videoErrorMessage = null
                    )
                } else {
                    val throwable = downloadResult.exceptionOrNull() ?: IllegalStateException("Video download failed")
                    if (firstError == null) firstError = throwable
                    dramaRepository.updateShotVideo(
                        shotId = shot.id,
                        videoStatus = AssetStatus.FAILED,
                        videoTaskId = generatedVideo.taskId,
                        videoUrl = generatedVideo.videoUrl,
                        videoLocalPath = shot.videoLocalPath,
                        videoErrorMessage = throwable.message
                    )
                }
            } else {
                val throwable = videoResult.exceptionOrNull() ?: IllegalStateException("Video generation failed")
                if (firstError == null) firstError = throwable
                dramaRepository.updateShotVideo(
                    shotId = shot.id,
                    videoStatus = AssetStatus.FAILED,
                    videoTaskId = shot.videoTaskId,
                    videoUrl = shot.videoUrl,
                    videoLocalPath = shot.videoLocalPath,
                    videoErrorMessage = throwable.message
                )
            }
        }

        val finalStatus = if (completed == shots.size) ProjectStatus.COMPLETED else ProjectStatus.FAILED
        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = finalStatus,
            currentStage = GenerationStage.VIDEO,
            generatedScript = project.generatedScript,
            errorMessage = firstError?.message
        )

        return if (completed > 0) Result.success(generated) else Result.failure(
            firstError ?: IllegalStateException("Video generation failed")
        )
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }

    private fun localImagePathToDataUri(path: String): String {
        val file = File(path)
        val mimeType = when (file.extension.lowercase()) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
        val base64 = Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)
        return "data:$mimeType;base64,$base64"
    }
}
