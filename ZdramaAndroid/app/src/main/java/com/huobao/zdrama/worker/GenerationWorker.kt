package com.huobao.zdrama.worker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
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
import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.AgnesStoryboardRepository
import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.AgnesVideoRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.data.media.LocalMp4Composer
import com.huobao.zdrama.domain.usecase.ComposeFinalVideoUseCase
import com.huobao.zdrama.domain.usecase.ExtractCharactersUseCase
import com.huobao.zdrama.domain.usecase.GenerateCharacterImagesUseCase
import com.huobao.zdrama.domain.usecase.GenerateProjectScriptUseCase
import com.huobao.zdrama.domain.usecase.GenerateStoryboardImagesUseCase
import com.huobao.zdrama.domain.usecase.GenerateStoryboardVideosUseCase
import com.huobao.zdrama.domain.usecase.GenerateStoryboardsUseCase
import com.huobao.zdrama.domain.usecase.RewriteEpisodeScriptUseCase
import com.huobao.zdrama.ui.project.ProjectDetailActivity
import kotlin.Result as KotlinResult

/**
 * 生成 Worker。所有 STAGE 均绑定 (projectId, episodeId)：
 * 一个剧集的一条生成链互不阻塞（uniqueWorkName 含 episodeId），
 * 多集可并行生成，互不影响（对齐 backend 按 episode_id 驱动 agent 的模式）。
 */
class GenerationWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): androidx.work.ListenableWorker.Result {
        val projectId = inputData.getLong(KEY_PROJECT_ID, 0L)
        val episodeId = inputData.getLong(KEY_EPISODE_ID, 0L)
        val stage = inputData.getString(KEY_STAGE).orEmpty()
        val forceRegenerate = inputData.getBoolean(KEY_FORCE_REGENERATE, false)
        if (projectId <= 0L || stage.isBlank()) return androidx.work.ListenableWorker.Result.failure()

        setForeground(createForegroundInfo(projectId, stage))

        val settings = AgnesSettingsStore(applicationContext).load()
        val dramaRepository = DramaRepository(applicationContext)
        val mediaDownloadRepository = MediaDownloadRepository(applicationContext)
        val result = when (stage) {
            STAGE_TEXT -> runText(projectId, episodeId, settings, dramaRepository)
            STAGE_REWRITE -> runRewrite(projectId, episodeId, settings, dramaRepository)
            STAGE_STORYBOARD -> runStoryboard(projectId, episodeId, settings, dramaRepository)
            STAGE_IMAGE -> runImages(projectId, episodeId, settings, dramaRepository, mediaDownloadRepository)
            STAGE_VIDEO -> runVideos(projectId, episodeId, settings, dramaRepository, mediaDownloadRepository)
            STAGE_FINAL_VIDEO -> runFinalVideo(projectId, episodeId, dramaRepository)
            STAGE_CHARACTER_EXTRACT -> runCharacterExtract(projectId, episodeId, settings, dramaRepository)
            STAGE_CHARACTER_IMAGE -> runCharacterImages(
                projectId, settings, dramaRepository, mediaDownloadRepository, forceRegenerate
            )
            STAGE_FULL -> runFullPipeline(projectId, episodeId, settings, dramaRepository, mediaDownloadRepository)
            else -> return androidx.work.ListenableWorker.Result.failure()
        }

        return if (result.isSuccess) {
            androidx.work.ListenableWorker.Result.success()
        } else {
            androidx.work.ListenableWorker.Result.failure()
        }
    }

    /** 一键全流程：作用于当前集（text → storyboard → images → videos → final video）。 */
    private suspend fun runFullPipeline(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository
    ): KotlinResult<Unit> {
        val scriptResult = runText(projectId, episodeId, settings, dramaRepository)
        if (scriptResult.isFailure) return scriptResult
        val storyboardResult = runStoryboard(projectId, episodeId, settings, dramaRepository)
        if (storyboardResult.isFailure) return storyboardResult
        val imageResult = runImages(projectId, episodeId, settings, dramaRepository, mediaDownloadRepository)
        if (imageResult.isFailure) return imageResult
        val videoResult = runVideos(projectId, episodeId, settings, dramaRepository, mediaDownloadRepository)
        if (videoResult.isFailure) return videoResult
        return runFinalVideo(projectId, episodeId, dramaRepository)
    }

    private suspend fun runText(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return GenerateProjectScriptUseCase(
            dramaRepository,
            AgnesTextRepository()
        ).execute(projectId, episodeId, settings).map { Unit }
    }

    private suspend fun runRewrite(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return RewriteEpisodeScriptUseCase(
            dramaRepository,
            AgnesTextRepository()
        ).execute(projectId, episodeId, settings).map { Unit }
    }

    private suspend fun runStoryboard(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return GenerateStoryboardsUseCase(
            dramaRepository,
            AgnesStoryboardRepository()
        ).execute(projectId, episodeId, settings).map { Unit }
    }

    private suspend fun runImages(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository
    ): KotlinResult<Unit> {
        return GenerateStoryboardImagesUseCase(
            dramaRepository,
            AgnesImageRepository(),
            mediaDownloadRepository
        ).execute(projectId, episodeId, settings).map { Unit }
    }

    private suspend fun runVideos(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository
    ): KotlinResult<Unit> {
        return GenerateStoryboardVideosUseCase(
            dramaRepository,
            AgnesVideoRepository(),
            mediaDownloadRepository
        ).execute(projectId, episodeId, settings).map { Unit }
    }

    private suspend fun runFinalVideo(
        projectId: Long,
        episodeId: Long,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return ComposeFinalVideoUseCase(
            dramaRepository,
            LocalMp4Composer(),
            applicationContext.filesDir
        ).execute(projectId, episodeId).map { Unit }
    }

    private suspend fun runCharacterExtract(
        projectId: Long,
        episodeId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository
    ): KotlinResult<Unit> {
        return ExtractCharactersUseCase(
            dramaRepository,
            AgnesTextRepository()
        ).execute(projectId, episodeId, settings).map { Unit }
    }

    private suspend fun runCharacterImages(
        projectId: Long,
        settings: AgnesSettings,
        dramaRepository: DramaRepository,
        mediaDownloadRepository: MediaDownloadRepository,
        forceRegenerate: Boolean
    ): KotlinResult<Unit> {
        return GenerateCharacterImagesUseCase(
            dramaRepository,
            AgnesImageRepository(),
            mediaDownloadRepository
        ).execute(projectId, settings, forceRegenerate).map { Unit }
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
        val notificationId = notificationIdForProject(projectId)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            ForegroundInfo(notificationId, notification)
        }
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
            STAGE_CHARACTER_EXTRACT -> R.string.generation_notification_character_extract
            STAGE_CHARACTER_IMAGE -> R.string.generation_notification_character_image
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
        const val STAGE_CHARACTER_EXTRACT = "character_extract"
        const val STAGE_CHARACTER_IMAGE = "character_image"
        const val STAGE_FULL = "full"

        private const val KEY_PROJECT_ID = "project_id"
        private const val KEY_EPISODE_ID = "episode_id"
        private const val KEY_STAGE = "stage"
        private const val KEY_FORCE_REGENERATE = "force_regenerate"
        private const val CHANNEL_ID = "generation"
        private const val NOTIFICATION_ID_BASE = 1000
        private const val NOTIFICATION_ID_PROJECT_RANGE = 100000

        /**
         * 入队生成任务。
         * - 普通 STAGE：唯一键含 episodeId，多集可并行
         * - [STAGE_CHARACTER_IMAGE]：项目级唯一键（角色立绘跨集共享），忽略 episodeId
         * - [forceRegenerate]：角色图确认覆盖时为 true，REPLACE 掉进行中的 skip 任务并真正重画
         */
        fun enqueue(
            context: Context,
            projectId: Long,
            episodeId: Long,
            stage: String,
            forceRegenerate: Boolean = false
        ) {
            val request = OneTimeWorkRequestBuilder<GenerationWorker>()
                .setInputData(
                    workDataOf(
                        KEY_PROJECT_ID to projectId,
                        KEY_EPISODE_ID to episodeId,
                        KEY_STAGE to stage,
                        KEY_FORCE_REGENERATE to forceRegenerate
                    )
                )
                .build()
            val policy = if (forceRegenerate) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP
            WorkManager.getInstance(context).enqueueUniqueWork(
                uniqueWorkName(projectId, episodeId, stage),
                policy,
                request
            )
        }

        fun cancelEpisode(context: Context, projectId: Long, episodeId: Long) {
            val workManager = WorkManager.getInstance(context)
            workNamesForEpisode(projectId, episodeId).forEach { workName ->
                workManager.cancelUniqueWork(workName)
            }
        }

        fun cancelCharacterImages(context: Context, projectId: Long) {
            WorkManager.getInstance(context).cancelUniqueWork(workNameForCharacterImages(projectId))
        }

        fun cancelProject(context: Context, projectId: Long, episodeIds: List<Long>) {
            episodeIds.forEach { episodeId -> cancelEpisode(context, projectId, episodeId) }
            cancelCharacterImages(context, projectId)
        }

        fun workNamesForEpisode(projectId: Long, episodeId: Long): List<String> {
            return listOf(
                STAGE_TEXT,
                STAGE_REWRITE,
                STAGE_STORYBOARD,
                STAGE_IMAGE,
                STAGE_VIDEO,
                STAGE_FINAL_VIDEO,
                STAGE_CHARACTER_EXTRACT,
                STAGE_FULL
            ).map { stage -> uniqueWorkName(projectId, episodeId, stage) }
        }

        /** 角色立绘是项目级资产，唯一键不含 episodeId，详情页必须单独观察这条。 */
        fun workNameForCharacterImages(projectId: Long): String {
            return "generation-$projectId-$STAGE_CHARACTER_IMAGE"
        }

        private fun uniqueWorkName(projectId: Long, episodeId: Long, stage: String): String {
            if (stage == STAGE_CHARACTER_IMAGE) {
                return workNameForCharacterImages(projectId)
            }
            return "generation-$projectId-$episodeId-$stage"
        }
    }
}