package com.huobao.zdrama.ui.project

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.databinding.ActivityProjectDetailBinding
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import com.huobao.zdrama.worker.GenerationWorker
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class ProjectDetailActivity : AppCompatActivity() {
    private lateinit var binding: ActivityProjectDetailBinding
    private lateinit var dramaRepository: DramaRepository
    private lateinit var settingsStore: AgnesSettingsStore
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private var projectId: Long = 0L
    private var hasGeneratedVideos = false
    private var hasFinalVideo = false
    private var finalVideoLocalPath: String? = null
    private var hasActiveGenerationWork = false
    private var activeGenerationRefreshJob: Job? = null
    private val generationWorkInfosByName = mutableMapOf<String, List<WorkInfo>>()
    private var promptExpanded = false
    private var boundPrompt: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProjectDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)

        dramaRepository = DramaRepository(this)
        settingsStore = AgnesSettingsStore(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(dramaRepository)
        getStoryboardsUseCase = GetStoryboardsUseCase(dramaRepository)

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        if (projectId <= 0L) {
            showMissingProject()
            return
        }
        binding.generateFullButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_FULL, R.string.project_full_queued)
        }
        binding.cancelGenerationButton.setOnClickListener { cancelGeneration() }
        binding.generateScriptButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_TEXT, R.string.project_script_queued)
        }
        binding.generateStoryboardButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_STORYBOARD, R.string.project_storyboard_queued)
        }
        binding.generateImagesButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_IMAGE, R.string.project_images_queued)
        }
        binding.generateVideosButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_VIDEO, R.string.project_videos_queued)
        }
        binding.composeFinalVideoButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_FINAL_VIDEO, R.string.project_final_video_queued)
        }
        binding.playFinalVideoButton.setOnClickListener { openFinalVideoPlayer() }
        binding.playVideosButton.setOnClickListener { openVideoPlayer() }
        binding.viewScriptButton.setOnClickListener { openScriptViewer() }
        binding.viewStoryboardButton.setOnClickListener { openStoryboardViewer() }
        binding.viewImagesButton.setOnClickListener { openImageGallery() }
        binding.viewApiLogButton.setOnClickListener { openApiLog() }
        binding.deleteProjectButton.setOnClickListener { confirmDeleteProject() }
        binding.promptToggle.setOnClickListener { togglePrompt() }
        observeGenerationWork(projectId)
        loadProject(projectId)
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadProject(projectId)
    }

    override fun onDestroy() {
        stopActiveGenerationRefresh()
        super.onDestroy()
    }

    private fun loadProject(projectId: Long) {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                showMissingProject()
            } else {
                val storyboards = getStoryboardsUseCase.execute(projectId)
                bindProject(project, storyboards)
            }
        }
    }

    private fun observeGenerationWork(projectId: Long) {
        GenerationWorker.workNamesForProject(projectId).forEach { workName ->
            WorkManager.getInstance(this)
                .getWorkInfosForUniqueWorkLiveData(workName)
                .observe(this) { workInfos -> handleWorkInfos(workName, workInfos) }
        }
    }

    private fun handleWorkInfos(workName: String, workInfos: List<WorkInfo>) {
        generationWorkInfosByName[workName] = workInfos
        val allWorkInfos = generationWorkInfosByName.values.flatten()
        val hasActiveWork = allWorkInfos.any { workInfo ->
            workInfo.state == WorkInfo.State.ENQUEUED || workInfo.state == WorkInfo.State.RUNNING
        }
        val hasFailedWork = allWorkInfos.any { workInfo -> workInfo.state == WorkInfo.State.FAILED }
        hasActiveGenerationWork = hasActiveWork
        setGenerationButtonsEnabled(!hasActiveGenerationWork)
        binding.cancelGenerationButton.visibility = if (hasActiveWork) View.VISIBLE else View.GONE
        binding.workStatusText.visibility = when {
            hasActiveWork || hasFailedWork -> View.VISIBLE
            else -> View.GONE
        }
        binding.workStatusText.text = when {
            hasActiveWork -> binding.workStatusText.text.takeIf { it.isNotBlank() }
                ?: getString(R.string.project_generation_running)
            hasFailedWork -> getString(R.string.project_generation_failed_background)
            else -> ""
        }
        if (hasActiveWork) {
            startActiveGenerationRefresh()
        } else {
            stopActiveGenerationRefresh()
            loadProject(projectId)
        }
    }

    private fun startActiveGenerationRefresh() {
        if (activeGenerationRefreshJob?.isActive == true) return
        activeGenerationRefreshJob = lifecycleScope.launch {
            while (isActive) {
                loadProject(projectId)
                delay(ACTIVE_REFRESH_INTERVAL_MS)
            }
        }
    }

    private fun stopActiveGenerationRefresh() {
        activeGenerationRefreshJob?.cancel()
        activeGenerationRefreshJob = null
    }

    private fun setGenerationButtonsEnabled(enabled: Boolean) {
        binding.generateFullButton.isEnabled = enabled
        binding.generateScriptButton.isEnabled = enabled
        binding.generateStoryboardButton.isEnabled = enabled
        binding.generateImagesButton.isEnabled = enabled
        binding.generateVideosButton.isEnabled = enabled
        binding.composeFinalVideoButton.isEnabled = enabled
    }

    private fun confirmGeneration(stage: String, queuedMessageRes: Int) {
        if (hasActiveGenerationWork) {
            Toast.makeText(this, R.string.project_generation_running, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            val storyboards = getStoryboardsUseCase.execute(projectId)
            val warningMessageRes = regenerationWarningMessageRes(stage, project, storyboards)
            if (warningMessageRes == null) {
                enqueueGeneration(stage, queuedMessageRes)
            } else {
                AlertDialog.Builder(this@ProjectDetailActivity)
                    .setTitle(R.string.project_regenerate_title)
                    .setMessage(warningMessageRes)
                    .setNegativeButton(R.string.project_regenerate_cancel, null)
                    .setPositiveButton(R.string.project_regenerate_confirm) { _, _ ->
                        enqueueGeneration(stage, queuedMessageRes)
                    }
                    .show()
            }
        }
    }

    private fun regenerationWarningMessageRes(
        stage: String,
        project: DramaProject?,
        storyboards: List<StoryboardShot>
    ): Int? {
        return when (stage) {
            GenerationWorker.STAGE_TEXT -> {
                if (!project?.generatedScript.isNullOrBlank()) R.string.project_regenerate_script_message else null
            }
            GenerationWorker.STAGE_STORYBOARD -> {
                if (storyboards.isNotEmpty()) R.string.project_regenerate_storyboard_message else null
            }
            GenerationWorker.STAGE_IMAGE -> {
                if (storyboards.any { it.imageStatus == AssetStatus.COMPLETED || isExistingFile(it.imageLocalPath) }) {
                    R.string.project_regenerate_images_message
                } else null
            }
            GenerationWorker.STAGE_VIDEO -> {
                if (storyboards.any { it.videoStatus == AssetStatus.COMPLETED || it.videoTaskId != null || isExistingFile(it.videoLocalPath) }) {
                    R.string.project_regenerate_videos_message
                } else null
            }
            GenerationWorker.STAGE_FINAL_VIDEO -> {
                if (project?.finalVideoStatus == AssetStatus.COMPLETED || isExistingFile(project?.finalVideoLocalPath)) {
                    R.string.project_regenerate_final_video_message
                } else null
            }
            GenerationWorker.STAGE_FULL -> {
                if (hasAnyGeneratedContent(project, storyboards)) R.string.project_regenerate_full_message else null
            }
            else -> null
        }
    }

    private fun hasAnyGeneratedContent(project: DramaProject?, storyboards: List<StoryboardShot>): Boolean {
        return !project?.generatedScript.isNullOrBlank() ||
            storyboards.isNotEmpty() ||
            project?.finalVideoStatus == AssetStatus.COMPLETED ||
            isExistingFile(project?.finalVideoLocalPath)
    }

    private fun enqueueGeneration(stage: String, messageRes: Int) {
        if (hasActiveGenerationWork) {
            Toast.makeText(this, R.string.project_generation_running, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            when (val preflight = checkGenerationPreflight(stage)) {
                is GenerationPreflight.Ready -> {
                    GenerationWorker.enqueue(this@ProjectDetailActivity, projectId, stage)
                    Toast.makeText(this@ProjectDetailActivity, messageRes, Toast.LENGTH_SHORT).show()
                    loadProject(projectId)
                }
                is GenerationPreflight.Blocked -> {
                    Toast.makeText(this@ProjectDetailActivity, preflight.messageRes, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private suspend fun checkGenerationPreflight(stage: String): GenerationPreflight {
        val requiresApiKey = stage != GenerationWorker.STAGE_FINAL_VIDEO
        if (requiresApiKey && settingsStore.load().apiKey.isBlank()) {
            return GenerationPreflight.Blocked(R.string.project_generation_missing_api_key)
        }

        val project = getProjectDetailUseCase.execute(projectId)
            ?: return GenerationPreflight.Blocked(R.string.project_missing)
        val storyboards = getStoryboardsUseCase.execute(projectId)

        return when (stage) {
            GenerationWorker.STAGE_STORYBOARD -> {
                if (project.generatedScript.isNullOrBlank()) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_script)
                } else {
                    GenerationPreflight.Ready
                }
            }
            GenerationWorker.STAGE_IMAGE -> {
                if (storyboards.isEmpty()) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_storyboards)
                } else {
                    GenerationPreflight.Ready
                }
            }
            GenerationWorker.STAGE_VIDEO -> {
                if (storyboards.isEmpty()) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_storyboards)
                } else if (storyboards.none { !it.imageLocalPath.isNullOrBlank() || !it.imageUrl.isNullOrBlank() }) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_images)
                } else {
                    GenerationPreflight.Ready
                }
            }
            GenerationWorker.STAGE_FINAL_VIDEO -> {
                if (storyboards.isEmpty()) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_storyboards)
                } else if (storyboards.any { !it.hasExistingLocalVideo() }) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_local_videos)
                } else {
                    GenerationPreflight.Ready
                }
            }
            else -> GenerationPreflight.Ready
        }
    }

    private fun cancelGeneration() {
        GenerationWorker.cancelProject(this, projectId)
        binding.cancelGenerationButton.visibility = View.GONE
        binding.workStatusText.visibility = View.VISIBLE
        binding.workStatusText.setText(R.string.project_generation_cancelled)
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project != null) {
                dramaRepository.updateProjectTextResult(
                    projectId = projectId,
                    status = ProjectStatus.CANCELLED,
                    currentStage = project.currentStage,
                    generatedScript = project.generatedScript,
                    errorMessage = getString(R.string.project_generation_cancelled)
                )
            }
            Toast.makeText(this@ProjectDetailActivity, R.string.project_generation_cancelled, Toast.LENGTH_SHORT).show()
            loadProject(projectId)
        }
    }

    private fun openVideoPlayer() {
        if (!hasGeneratedVideos) {
            Toast.makeText(this, R.string.project_no_videos, Toast.LENGTH_SHORT).show()
            return
        }
        startActivity(
            Intent(this, VideoPlayerActivity::class.java)
                .putExtra(VideoPlayerActivity.EXTRA_PROJECT_ID, projectId)
        )
    }

    private fun openFinalVideoPlayer() {
        val path = finalVideoLocalPath
        if (!hasFinalVideo || path.isNullOrBlank()) {
            Toast.makeText(this, R.string.project_no_final_video, Toast.LENGTH_SHORT).show()
            return
        }
        startActivity(
            Intent(this, VideoPlayerActivity::class.java)
                .putExtra(VideoPlayerActivity.EXTRA_VIDEO_PATH, path)
        )
    }

    private fun openScriptViewer() {
        startActivity(
            Intent(this, ScriptViewerActivity::class.java)
                .putExtra(ScriptViewerActivity.EXTRA_PROJECT_ID, projectId)
        )
    }

    private fun openStoryboardViewer() {
        startActivity(
            Intent(this, StoryboardViewerActivity::class.java)
                .putExtra(StoryboardViewerActivity.EXTRA_PROJECT_ID, projectId)
        )
    }

    private fun openImageGallery() {
        startActivity(
            Intent(this, ImageGalleryActivity::class.java)
                .putExtra(ImageGalleryActivity.EXTRA_PROJECT_ID, projectId)
        )
    }

    private fun openApiLog() {
        startActivity(Intent(this, ApiLogActivity::class.java))
    }

    private fun bindPrompt(prompt: String) {
        if (boundPrompt == prompt) {
            // 同一段文本重复绑定不重置展开状态,只更新 toggle 文案
            applyPromptExpanded()
            return
        }
        boundPrompt = prompt
        promptExpanded = false
        binding.promptText.text = prompt
        // 用 post 等 TextView 排版完成后再判断行数
        binding.promptText.post {
            val needsToggle = binding.promptText.lineCount > PROMPT_COLLAPSED_MAX_LINES
            binding.promptToggle.visibility = if (needsToggle) View.VISIBLE else View.GONE
            applyPromptExpanded()
        }
    }

    private fun togglePrompt() {
        promptExpanded = !promptExpanded
        applyPromptExpanded()
    }

    private fun applyPromptExpanded() {
        binding.promptText.maxLines =
            if (promptExpanded) Int.MAX_VALUE else PROMPT_COLLAPSED_MAX_LINES
        binding.promptToggle.setText(
            if (promptExpanded) R.string.project_prompt_collapse else R.string.project_prompt_expand
        )
    }

    private fun confirmDeleteProject() {
        AlertDialog.Builder(this)
            .setTitle(R.string.project_delete_title)
            .setMessage(R.string.project_delete_message)
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> deleteProject() }
            .show()
    }

    private fun deleteProject() {
        GenerationWorker.cancelProject(this, projectId)
        lifecycleScope.launch {
            val deleted = dramaRepository.deleteProject(projectId)
            if (deleted) {
                Toast.makeText(this@ProjectDetailActivity, R.string.project_deleted, Toast.LENGTH_SHORT).show()
                finish()
            } else {
                Toast.makeText(this@ProjectDetailActivity, R.string.project_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun bindProject(project: DramaProject, storyboards: List<StoryboardShot>) {
        hasGeneratedVideos = storyboards.any { it.hasPlayableVideo() }
        finalVideoLocalPath = project.finalVideoLocalPath
        hasFinalVideo = project.finalVideoStatus == AssetStatus.COMPLETED && isExistingFile(project.finalVideoLocalPath)
        binding.playVideosButton.isEnabled = hasGeneratedVideos
        binding.playFinalVideoButton.isEnabled = hasFinalVideo
        binding.viewScriptButton.isEnabled = !project.generatedScript.isNullOrBlank()
        binding.viewStoryboardButton.isEnabled = storyboards.isNotEmpty()
        binding.viewImagesButton.isEnabled = storyboards.any {
            isExistingFile(it.imageLocalPath) || !it.imageUrl.isNullOrBlank()
        }
        bindGenerationButtonTexts(project, storyboards)
        binding.titleText.text = project.title
        binding.statusText.text = getString(R.string.project_status_label) + "：${project.status.toDisplayText()}\n" +
            getString(R.string.project_stage_label) + "：${project.currentStage.toDisplayText()}"
        bindActiveGenerationStatus(project, storyboards)
        bindPrompt(project.prompt)
        binding.metaText.text = buildString {
            append(getString(R.string.project_style_label)).append("：").append(project.style).append('\n')
            append(getString(R.string.project_audience_label)).append("：").append(project.targetAudience).append('\n')
            append(getString(R.string.project_aspect_ratio_label)).append("：").append(project.aspectRatio).append('\n')
            append(getString(R.string.project_shot_count_label)).append("：").append(project.shotCount).append('\n')
            append(getString(R.string.project_duration_label)).append("：").append(project.shotDurationSeconds).append('\n')
            append(getString(R.string.project_final_video_status_label)).append("：").append(project.finalVideoStatus.toDisplayText())
            project.finalVideoLocalPath?.takeIf { it.isNotBlank() }?.let { path ->
                append('\n').append(getString(R.string.project_final_video_local_path_label)).append("：").append(path)
            }
            project.finalVideoErrorMessage?.takeIf { it.isNotBlank() }?.let { error ->
                append('\n').append(getString(R.string.project_error_label)).append("：").append(error)
            }
            project.errorMessage?.takeIf { it.isNotBlank() }?.let { error ->
                append('\n').append(getString(R.string.project_error_label)).append("：").append(error)
            }
        }
    }

    private fun ProjectStatus.toDisplayText(): String {
        return getString(
            when (this) {
                ProjectStatus.DRAFT -> R.string.status_draft
                ProjectStatus.PROCESSING -> R.string.status_processing
                ProjectStatus.COMPLETED -> R.string.status_completed
                ProjectStatus.FAILED -> R.string.status_failed
                ProjectStatus.CANCELLED -> R.string.status_cancelled
            }
        )
    }

    private fun GenerationStage.toDisplayText(): String {
        return getString(
            when (this) {
                GenerationStage.NONE -> R.string.stage_none
                GenerationStage.TEXT -> R.string.stage_text
                GenerationStage.STORYBOARD -> R.string.stage_storyboard
                GenerationStage.IMAGE -> R.string.stage_image
                GenerationStage.VIDEO -> R.string.stage_video
                GenerationStage.FINAL_VIDEO -> R.string.stage_final_video
            }
        )
    }

    private fun AssetStatus.toDisplayText(): String {
        return getString(
            when (this) {
                AssetStatus.PENDING -> R.string.asset_pending
                AssetStatus.PROCESSING -> R.string.asset_processing
                AssetStatus.COMPLETED -> R.string.asset_completed
                AssetStatus.FAILED -> R.string.asset_failed
            }
        )
    }

    private fun StoryboardShot.hasPlayableVideo(): Boolean {
        return hasExistingLocalVideo() || !videoUrl.isNullOrBlank()
    }

    private fun StoryboardShot.hasExistingLocalVideo(): Boolean {
        return isExistingFile(videoLocalPath)
    }

    private fun isExistingFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }

    private fun bindGenerationButtonTexts(project: DramaProject, storyboards: List<StoryboardShot>) {
        binding.generateFullButton.setText(
            if (hasAnyGeneratedContent(project, storyboards)) R.string.project_regenerate_full else R.string.project_generate_full
        )
        binding.generateScriptButton.setText(
            if (!project.generatedScript.isNullOrBlank()) R.string.project_regenerate_script else R.string.project_generate_script
        )
        binding.generateStoryboardButton.setText(
            if (storyboards.isNotEmpty()) R.string.project_regenerate_storyboards else R.string.project_generate_storyboards
        )
        binding.generateImagesButton.setText(
            if (storyboards.any { it.imageStatus == AssetStatus.COMPLETED || isExistingFile(it.imageLocalPath) }) {
                R.string.project_regenerate_images
            } else {
                R.string.project_generate_images
            }
        )
        binding.generateVideosButton.setText(
            if (storyboards.any { it.videoStatus == AssetStatus.COMPLETED || it.videoTaskId != null || isExistingFile(it.videoLocalPath) }) {
                R.string.project_regenerate_videos
            } else {
                R.string.project_generate_videos
            }
        )
        binding.composeFinalVideoButton.setText(
            if (project.finalVideoStatus == AssetStatus.COMPLETED || isExistingFile(project.finalVideoLocalPath)) {
                R.string.project_recompose_final_video
            } else {
                R.string.project_compose_final_video
            }
        )
    }

    private fun bindActiveGenerationStatus(project: DramaProject, storyboards: List<StoryboardShot>) {
        if (!hasActiveGenerationWork) return
        binding.workStatusText.visibility = View.VISIBLE
        binding.workStatusText.text = buildActiveGenerationStatus(project, storyboards)
    }

    private fun buildActiveGenerationStatus(project: DramaProject, storyboards: List<StoryboardShot>): String {
        return when (project.currentStage) {
            GenerationStage.IMAGE -> buildImageProgressText(storyboards)
            GenerationStage.VIDEO -> buildVideoProgressText(storyboards)
            else -> getString(R.string.project_generation_running_stage, project.currentStage.toDisplayText())
        }
    }

    private fun buildImageProgressText(storyboards: List<StoryboardShot>): String {
        return buildMediaProgressText(
            storyboards = storyboards,
            selector = { shot -> shot.imageStatus },
            currentTextRes = R.string.project_generation_image_current_shot,
            summaryTextRes = R.string.project_generation_image_summary
        )
    }

    private fun buildVideoProgressText(storyboards: List<StoryboardShot>): String {
        return buildMediaProgressText(
            storyboards = storyboards,
            selector = { shot -> shot.videoStatus },
            currentTextRes = R.string.project_generation_video_current_shot,
            summaryTextRes = R.string.project_generation_video_summary
        )
    }

    private fun buildMediaProgressText(
        storyboards: List<StoryboardShot>,
        selector: (StoryboardShot) -> AssetStatus,
        currentTextRes: Int,
        summaryTextRes: Int
    ): String {
        if (storyboards.isEmpty()) return getString(R.string.project_generation_running)
        val total = storyboards.size
        val completed = storyboards.count { selector(it) == AssetStatus.COMPLETED }
        val failed = storyboards.count { selector(it) == AssetStatus.FAILED }
        val pending = storyboards.count { selector(it) == AssetStatus.PENDING }
        val current = processingShotPosition(storyboards, selector)
        val currentText = if (current != null) {
            getString(currentTextRes, current.first, total, current.second.shotNumber)
        } else {
            getString(R.string.project_generation_waiting_next_shot)
        }
        val summaryText = getString(summaryTextRes, completed, total, failed, pending)
        return "$currentText\n$summaryText"
    }

    private fun processingShotPosition(
        storyboards: List<StoryboardShot>,
        selector: (StoryboardShot) -> AssetStatus
    ): Pair<Int, StoryboardShot>? {
        storyboards.forEachIndexed { index, shot ->
            if (selector(shot) == AssetStatus.PROCESSING) return Pair(index + 1, shot)
        }
        return null
    }

    private fun showMissingProject() {
        Toast.makeText(this, R.string.project_missing, Toast.LENGTH_SHORT).show()
        finish()
    }

    companion object {
        const val EXTRA_PROJECT_ID = "extra_project_id"
        private const val ACTIVE_REFRESH_INTERVAL_MS = 1500L
        private const val PROMPT_COLLAPSED_MAX_LINES = 6
    }

    private sealed class GenerationPreflight {
        object Ready : GenerationPreflight()
        data class Blocked(val messageRes: Int) : GenerationPreflight()
    }
}
