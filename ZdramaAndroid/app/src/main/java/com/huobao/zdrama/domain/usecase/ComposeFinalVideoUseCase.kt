package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.media.LocalMp4Composer
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import java.io.File

class ComposeFinalVideoUseCase(
    private val dramaRepository: DramaRepository,
    private val composer: LocalMp4Composer,
    private val appFilesDir: File
) {
    suspend fun execute(projectId: Long): Result<String> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("项目不存在"))
        val shots = dramaRepository.getStoryboards(projectId).sortedBy { it.shotNumber }
        if (shots.isEmpty()) {
            val throwable = IllegalArgumentException("请先生成分镜")
            markFailed(projectId, throwable.message)
            return Result.failure(throwable)
        }

        val missingVideo = shots.firstOrNull { shot ->
            shot.videoStatus != AssetStatus.COMPLETED || !isExistingLocalFile(shot.videoLocalPath)
        }
        if (missingVideo != null) {
            val throwable = IllegalArgumentException("请先生成并下载全部分镜视频后再合成成片")
            markFailed(projectId, throwable.message)
            return Result.failure(throwable)
        }

        dramaRepository.updateProjectFinalVideo(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.FINAL_VIDEO,
            finalVideoStatus = AssetStatus.PROCESSING,
            finalVideoLocalPath = project.finalVideoLocalPath,
            finalVideoErrorMessage = null,
            errorMessage = null
        )

        val outputFile = File(appFilesDir, "generated/$projectId/final_video.mp4")
        val result = composer.compose(
            inputPaths = shots.mapNotNull { it.videoLocalPath },
            outputPath = outputFile.absolutePath
        )
        result.onSuccess { outputPath ->
            dramaRepository.updateProjectFinalVideo(
                projectId = projectId,
                status = ProjectStatus.COMPLETED,
                currentStage = GenerationStage.FINAL_VIDEO,
                finalVideoStatus = AssetStatus.COMPLETED,
                finalVideoLocalPath = outputPath,
                finalVideoErrorMessage = null,
                errorMessage = null
            )
        }.onFailure { throwable ->
            markFailed(projectId, throwable.message)
        }
        return result
    }

    private suspend fun markFailed(projectId: Long, message: String?) {
        dramaRepository.updateProjectFinalVideo(
            projectId = projectId,
            status = ProjectStatus.FAILED,
            currentStage = GenerationStage.FINAL_VIDEO,
            finalVideoStatus = AssetStatus.FAILED,
            finalVideoLocalPath = null,
            finalVideoErrorMessage = message,
            errorMessage = message
        )
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }
}
