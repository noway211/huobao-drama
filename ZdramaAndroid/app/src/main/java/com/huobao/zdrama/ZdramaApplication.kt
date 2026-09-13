package com.huobao.zdrama

import android.app.Application
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.worker.GenerationWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 进程启动时一次性修复"僵尸"生成状态。
 *
 * 场景:上一次进程运行时用户点了生成,DB 里项目被写成 PROCESSING,进程随后被强杀。
 * WorkManager 重启后会把中断的 RUNNING 任务自动重排为 ENQUEUED 尝试重试,
 * 但我们不希望这种"影子重试":用户看到的是无声的生成中,却没有前台通知,任务
 * 实际上很可能失败。
 *
 * 策略:进程冷启动时,直接
 *   1. 取消所有生成相关的 WorkManager 唯一任务(避免影子重试)
 *   2. 把 DB 里所有 PROCESSING 状态的项目改成 FAILED,由用户手动重新触发
 */
class ZdramaApplication : Application() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        backfillStoryboardEpisodeIds()
        resetOrphanGenerationJobs()
    }

    /** 多集改造前创建的分镜 episode_id 可能为 NULL（按集查询会漏），启动时兜底回填一次。 */
    private fun backfillStoryboardEpisodeIds() {
        val repository = DramaRepository(this)
        scope.launch {
            repository.backfillStoryboardEpisodeIds()
        }
    }

    private fun resetOrphanGenerationJobs() {
        val repository = DramaRepository(this)
        scope.launch {
            val projects = repository.getProjects()
            projects.filter { it.status == ProjectStatus.PROCESSING }.forEach { project ->
                GenerationWorker.cancelProject(
                    this@ZdramaApplication,
                    project.id,
                    repository.getEpisodes(project.id).map { it.id }
                )
                repository.updateProjectTextResult(
                    projectId = project.id,
                    status = ProjectStatus.FAILED,
                    currentStage = project.currentStage,
                    generatedScript = project.generatedScript,
                    errorMessage = ORPHAN_ERROR
                )
            }
        }
    }

    companion object {
        private const val ORPHAN_ERROR = "生成任务中断（应用被关闭），请重新开始"
    }
}
