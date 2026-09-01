package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.media.LocalMp4Composer
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import java.io.File

/**
 * 每集独立成片（对齐 backend video_merges.episodeId 语义）：
 * 拼接某集的全部分镜视频 → generated/<projectId>/episode_<episodeId>/final_video.mp4，
 * 结果与状态写入 episodes 表的 3 个成片列（v12 迁移新增）。
 */
class ComposeFinalVideoUseCase(
    private val dramaRepository: DramaRepository,
    private val composer: LocalMp4Composer,
    private val appFilesDir: File
) {
    suspend fun execute(projectId: Long, episodeId: Long): Result<String> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("项目不存在"))
        val episode = dramaRepository.getEpisodeById(episodeId)
            ?: dramaRepository.getEpisodeForProject(projectId)
            ?: return Result.failure(IllegalArgumentException("剧集不存在"))
        val shots = dramaRepository.getStoryboards(projectId, episodeId).sortedBy { it.shotNumber }
        if (shots.isEmpty()) {
            val throwable = IllegalArgumentException("请先生成分镜")
            markFailed(projectId, episodeId, throwable.message)
            return Result.failure(throwable)
        }

        val missingVideo = shots.firstOrNull { shot ->
            shot.videoStatus != AssetStatus.COMPLETED || !isExistingLocalFile(shot.videoLocalPath)
        }
        if (missingVideo != null) {
            val throwable = IllegalArgumentException("请先生成并下载全部分镜视频后再合成成片")
            markFailed(projectId, episodeId, throwable.message)
            return Result.failure(throwable)
        }

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.FINAL_VIDEO,
            generatedScript = project.generatedScript,
            errorMessage = null
        )
        dramaRepository.updateEpisodeFinalVideo(
            episodeId = episode.id,
            finalVideoStatus = AssetStatus.PROCESSING,
            finalVideoLocalPath = episode.finalVideoLocalPath,
            finalVideoErrorMessage = null
        )

        val outputDir = File(appFilesDir, "generated/$projectId/episode_${episode.id}")
        if (!outputDir.exists() && !outputDir.mkdirs()) {
            val throwable = IllegalStateException("无法创建成片输出目录")
            markFailed(projectId, episodeId, throwable.message)
            return Result.failure(throwable)
        }
        val outputFile = File(outputDir, "final_video.mp4")
        // 覆盖合成前清理旧文件，避免残留长度错误的成片
        if (outputFile.exists()) outputFile.delete()

        val result = composer.compose(
            inputPaths = shots.mapNotNull { it.videoLocalPath },
            outputPath = outputFile.absolutePath
        )
        result.onSuccess { outputPath ->
            dramaRepository.updateProjectTextResult(
                projectId = projectId,
                status = ProjectStatus.COMPLETED,
                currentStage = GenerationStage.FINAL_VIDEO,
                generatedScript = project.generatedScript,
                errorMessage = null
            )
            dramaRepository.updateEpisodeFinalVideo(
                episodeId = episodeId,
                finalVideoStatus = AssetStatus.COMPLETED,
                finalVideoLocalPath = outputPath,
                finalVideoErrorMessage = null
            )
        }.onFailure { throwable ->
            markFailed(projectId, episodeId, throwable.message)
        }
        return result
    }

    private suspend fun markFailed(projectId: Long, episodeId: Long, message: String?) {
        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.FAILED,
            currentStage = GenerationStage.FINAL_VIDEO,
            generatedScript = null,
            errorMessage = message
        )
        dramaRepository.updateEpisodeFinalVideo(
            episodeId = episodeId,
            finalVideoStatus = AssetStatus.FAILED,
            finalVideoLocalPath = null,
            finalVideoErrorMessage = message
        )
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }
}