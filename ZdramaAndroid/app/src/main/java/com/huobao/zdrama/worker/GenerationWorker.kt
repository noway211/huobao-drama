package com.huobao.zdrama.worker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.huobao.zdrama.R
import com.huobao.zdrama.data.media.LocalMp4Composer
import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.AgnesStoryboardRepository
import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.AgnesVideoRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.domain.usecase.ComposeFinalVideoUseCase
import com.huobao.zdrama.domain.usecase.GenerateProjectScriptUseCase
import com.huobao.zdrama.domain.usecase.GenerateStoryboardImagesUseCase
import com.huobao.zdrama.domain.usecase.GenerateStoryboardVideosUseCase
import com.huobao.zdrama.domain.usecase.GenerateStoryboardsUseCase
import com.huobao.zdrama.domain.usecase.RewriteEpisodeScriptUseCase
import com.huobao.zdrama.ui.project.ProjectDetailActivity
import kotlin.Result as KotlinResult

class GenerationWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): androidx.work.ListenableWorker.Result {
        val projectId = inputData.getLong(KEY_PROJECT_ID, 0L)
        val stage = inputData.getString(KEY_STAGE).orEmpty()
        if (projectId <= 0L || stage.isBlank()) return androidx.work.ListenableWorker.Result.failure()

        setForeground(createForegroundInfo(projectId, stage))

        val settings = AgnesSettingsStore(applicationContext).load()
        val dramaRepository = DramaRepository(applicationContext)
        val mediaDownloadRepository = MediaDownloadRepository(applicationContext)
        val result = when (stage) {
            STAGE_TEXT -> runText(projectId, settings, dramaRepository)
            STAGE_REWRITE -> runRewrite(projectId, settings, dramaRepository)
            STAGE_STORYBOARD -> runStoryboard(projectId, settings, dramaRepository)
            STAGE_IMAGE -> runImages(projectId, settings, dramaRepository, mediaDownloadRepository)
            STAGE_VIDEO -> runVideos(projectId, settings, dramaRepository, mediaDownloadRepository)
            STAGE_FINAL_VIDEO -> runFinalVideo(projectId, dramaRepository)
            STAGE_FULL -> runFullPipeline(projectId, settings, dramaRepository, mediaDownloadRepository)
            else -> return androidx.work.ListenableWorker.Result.failure()
        }

        return if (result.isSuccess) {
            androidx.work.ListenableWorker.Result.success()
        } else {
            androidx.work.ListenableWorker.Result.failure()
        }
    }

    private suspend fun runFullPipeline(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository
    ): KotlinResult<Unit> {
        val scriptResult = runText(projectId, settings, dramaRepository)
        if (scriptResult.isFailure) return scriptResult
        val storyboardResult = runStoryboard(projectId, settings, dramaRepository)
        if (storyboardResult.isFailure) return storyboardResult
        val imageResult = runImages(projectId, settings, dramaRepository, mediaDownloadRepository)
        if (imageResult.isFailure) return imageResult
        val videoResult = runVideos(projectId, settings, dramaRepository, mediaDownloadRepository)
        if (videoResult.isFailure) return videoResult
        return runFinalVideo(projectId, dramaRepository)
    }

    private suspend fun runText(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return GenerateProjectScriptUseCase(
            dramaRepository,
            AgnesTextRepository()
        ).execute(projectId, settings).map { Unit }
    }

    private suspend fun runRewrite(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return RewriteEpisodeScriptUseCase(
            dramaRepository,
            AgnesTextRepository()
        ).execute(projectId, settings).map { Unit }
    }

    private suspend fun runStoryboard(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return GenerateStoryboardsUseCase(
            dramaRepository,
            AgnesStoryboardRepository()
        ).execute(projectId, settings).map { Unit }
    }

    private suspend fun runImages(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository
    ): KotlinResult<Unit> {
        return GenerateStoryboardImagesUseCase(
            dramaRepository,
            AgnesImageRepository(),
            mediaDownloadRepository
        ).execute(projectId, settings).map { Unit }
    }

    private suspend fun runVideos(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository
    ): KotlinResult<Unit> {
        return GenerateStoryboardVideosUseCase(
            dramaRepository,
            AgnesVideoRepository(),
            mediaDownloadRepository
        ).execute(projectId, settings).map { Unit }
    }

    private suspend fun runFinalVideo(
        projectId: Long,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return ComposeFinalVideoUseCase(
            dramaRepository,
            LocalMp4Composer(),
            applicationContext.filesDir
        ).execute(projectId).map { Unit }
    }

    private fun createForegroundInfo(projectId: Long, stage: String): ForegroundInfo {
        ensureNotificationChannel()
        val contentIntent = createProjectDetailPendingIntent(projectId)
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(applicationContext.getString(R.string.generation_notification_title))
            .setContentText(applicationContext.getString(stageMessageRes(stage)))
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
        return ForegroundInfo(notificationIdForProject(projectId), notification)
    }

    private fun notificationIdForProject(projectId: Long): Int {
        return NOTIFICATION_ID_BASE + (projectId % NOTIFICATION_ID_PROJECT_RANGE).toInt()
    }

    private fun createProjectDetailPendingIntent(projectId: Long): PendingIntent {
        val intent = Intent(applicationContext, ProjectDetailActivity::class.java)
            .putExtra(ProjectDetailActivity.EXTRA_PROJECT_ID, projectId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            applicationContext,
            projectId.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            applicationContext.getString(R.string.generation_notification_channel),
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    private fun stageMessageRes(stage: String): Int {
        return when (stage) {
            STAGE_TEXT -> R.string.generation_notification_text
            STAGE_REWRITE -> R.string.project_rewriting_script
            STAGE_STORYBOARD -> R.string.generation_notification_storyboard
            STAGE_IMAGE -> R.string.generation_notification_image
            STAGE_VIDEO -> R.string.generation_notification_video
            STAGE_FINAL_VIDEO -> R.string.generation_notification_final_video
            STAGE_FULL -> R.string.generation_notification_full
            else -> R.string.generation_notification_title
        }
    }

    companion object {
        const val STAGE_TEXT = "text"
        const val STAGE_REWRITE = "rewrite"
        const val STAGE_STORYBOARD = "storyboard"
        const val STAGE_IMAGE = "image"
        const val STAGE_VIDEO = "video"
        const val STAGE_FINAL_VIDEO = "final_video"
        const val STAGE_FULL = "full"

        private const val KEY_PROJECT_ID = "project_id"
        private const val KEY_STAGE = "stage"
        private const val CHANNEL_ID = "generation"
        private const val NOTIFICATION_ID_BASE = 1000
        private const val NOTIFICATION_ID_PROJECT_RANGE = 100000

        fun enqueue(context: Context, projectId: Long, stage: String) {
            val request = OneTimeWorkRequestBuilder<GenerationWorker>()
                .setInputData(
                    workDataOf(
                        KEY_PROJECT_ID to projectId,
                        KEY_STAGE to stage
                    )
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                uniqueWorkName(projectId, stage),
                ExistingWorkPolicy.KEEP,
                request
            )
        }

        fun cancelProject(context: Context, projectId: Long) {
            val workManager = WorkManager.getInstance(context)
            workNamesForProject(projectId).forEach { workName ->
                workManager.cancelUniqueWork(workName)
            }
        }

        fun workNamesForProject(projectId: Long): List<String> {
            return listOf(
                STAGE_TEXT,
                STAGE_REWRITE,
                STAGE_STORYBOARD,
                STAGE_IMAGE,
                STAGE_VIDEO,
                STAGE_FINAL_VIDEO,
                STAGE_FULL
            ).map { stage -> uniqueWorkName(projectId, stage) }
        }

        private fun uniqueWorkName(projectId: Long, stage: String): String {
            return "generation-$projectId-$stage"
        }
    }
}
