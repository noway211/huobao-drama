package com.huobao.zdrama.ui.project

import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
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
import com.huobao.zdrama.domain.model.Episode
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetCharactersUseCase
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
    private lateinit var getCharactersUseCase: GetCharactersUseCase
    private var projectId: Long = 0L
    private var projectTitle: String? = null
    private var currentEpisodeId: Long = 0L
    private var episodes: List<Episode> = emptyList()
    private var hasGeneratedVideos = false
    private var hasFinalVideo = false
    private var finalVideoLocalPath: String? = null
    private var hasActiveGenerationWork = false
    private var activeGenerationRefreshJob: Job? = null
    private val generationWorkInfosByName = mutableMapOf<String, List<WorkInfo>>()
    private val observedWorkNames = mutableSetOf<String>()
    private var promptExpanded = false
    private var boundPrompt: String? = null
    private var cachedCharacterCount: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProjectDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)

        dramaRepository = DramaRepository(this)
        settingsStore = AgnesSettingsStore(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(dramaRepository)
        getStoryboardsUseCase = GetStoryboardsUseCase(dramaRepository)
        getCharactersUseCase = GetCharactersUseCase(dramaRepository)

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
        binding.rewriteScriptButton.setOnClickListener { confirmRewrite() }
        binding.viewScriptButton.setOnClickListener { openScriptViewer() }
        binding.viewStoryboardButton.setOnClickListener { openStoryboardViewer() }
        binding.viewImagesButton.setOnClickListener { openImageGallery() }
        binding.generateCharactersButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_CHARACTER_EXTRACT, R.string.project_characters_queued)
        }
        binding.viewCharactersButton.setOnClickListener { openCharacterList() }
        binding.generateCharacterImagesButton.setOnClickListener {
            confirmGeneration(GenerationWorker.STAGE_CHARACTER_IMAGE, R.string.project_character_image_queued)
        }
        binding.viewApiLogButton.setOnClickListener { openApiLog() }
        binding.deleteProjectButton.setOnClickListener { confirmDeleteProject() }
        binding.promptToggle.setOnClickListener { togglePrompt() }
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
                val loadedEpisodes = dramaRepository.getEpisodes(projectId)
                episodes = loadedEpisodes
                if (currentEpisodeId <= 0L || loadedEpisodes.none { it.id == currentEpisodeId }) {
                    currentEpisodeId = loadedEpisodes.firstOrNull()?.id ?: 0L
                }
                bindEpisodeChips(loadedEpisodes)
                observeGenerationWork(projectId, loadedEpisodes)
                val storyboards = if (currentEpisodeId > 0L) {
                    getStoryboardsUseCase.execute(projectId, currentEpisodeId)
                } else {
                    emptyList()
                }
                val episode = loadedEpisodes.firstOrNull { it.id == currentEpisodeId }
                val characters = getCharactersUseCase.execute(projectId)
                cachedCharacterCount = characters.size
                bindProject(project, episode, storyboards, characters)
            }
        }
    }

    /**
     * 每集注册一次 WorkManager LiveData 观察（用 observedWorkNames 去重）。
     * 其他集/本集的生成任务都会触发 handleWorkInfos → 刷新按钮状态 + 重载当前集数据。
     */
    private fun observeGenerationWork(projectId: Long, episodes: List<Episode>) {
        episodes.forEach { episode ->
            GenerationWorker.workNamesForEpisode(projectId, episode.id).forEach { workName ->
                if (observedWorkNames.add(workName)) {
                    WorkManager.getInstance(this)
                        .getWorkInfosForUniqueWorkLiveData(workName)
                        .observe(this) { workInfos -> handleWorkInfos(workName, workInfos) }
                }
            }
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
        binding.rewriteScriptButton.isEnabled = enabled
        binding.generateStoryboardButton.isEnabled = enabled
        binding.generateImagesButton.isEnabled = enabled
        binding.generateVideosButton.isEnabled = enabled
        binding.composeFinalVideoButton.isEnabled = enabled
        binding.generateCharactersButton.isEnabled = enabled
        binding.viewCharactersButton.isEnabled = enabled
        binding.generateCharacterImagesButton.isEnabled = enabled
    }

    private fun confirmGeneration(stage: String, queuedMessageRes: Int) {
        if (hasActiveGenerationWork) {
            Toast.makeText(this, R.string.project_generation_running, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            val episode = currentEpisode()
            val storyboards = getCurrentEpisodeStoryboards()
            val warningMessageRes = regenerationWarningMessageRes(stage, project, episode, storyboards)
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
        episode: Episode?,
        storyboards: List<StoryboardShot>
    ): Int? {
        return when (stage) {
            GenerationWorker.STAGE_TEXT -> {
                if (!episode?.scriptContent.isNullOrBlank()) R.string.project_regenerate_script_message else null
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
                if (episode?.finalVideoStatus == AssetStatus.COMPLETED || isExistingFile(episode?.finalVideoLocalPath)) {
                    R.string.project_regenerate_final_video_message
                } else null
            }
            GenerationWorker.STAGE_FULL -> {
                if (hasAnyGeneratedContent(project, episode, storyboards)) R.string.project_regenerate_full_message else null
            }
            GenerationWorker.STAGE_CHARACTER_EXTRACT -> {
                if (cachedCharacterCount > 0) R.string.project_regenerate_characters_message else null
            }
            GenerationWorker.STAGE_CHARACTER_IMAGE -> {
                if (cachedCharacterCount > 0) R.string.project_regenerate_character_images_message else null
            }
            else -> null
        }
    }

    private fun hasAnyGeneratedContent(
        project: DramaProject?,
        episode: Episode?,
        storyboards: List<StoryboardShot>
    ): Boolean {
        return !episode?.scriptContent.isNullOrBlank() ||
            storyboards.isNotEmpty() ||
            episode?.finalVideoStatus == AssetStatus.COMPLETED ||
            isExistingFile(episode?.finalVideoLocalPath)
    }

    private fun enqueueGeneration(stage: String, messageRes: Int) {
        if (hasActiveGenerationWork) {
            Toast.makeText(this, R.string.project_generation_running, Toast.LENGTH_SHORT).show()
            return
        }
        if (currentEpisodeId <= 0L) {
            Toast.makeText(this, R.string.project_missing, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            when (val preflight = checkGenerationPreflight(stage)) {
                is GenerationPreflight.Ready -> {
                    GenerationWorker.enqueue(this@ProjectDetailActivity, projectId, currentEpisodeId, stage)
                    Toast.makeText(this@ProjectDetailActivity, messageRes, Toast.LENGTH_SHORT).show()
                    loadProject(projectId)
                }
                is GenerationPreflight.Blocked -> {
                    Toast.makeText(this@ProjectDetailActivity, preflight.messageRes, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    /** 当前选中集；兜底回退到最新一集（保持 0L 时旧逻辑的 getEpisodeForProject 语义）。 */
    private suspend fun currentEpisode(): Episode? {
        return if (currentEpisodeId > 0L) {
            dramaRepository.getEpisodeById(currentEpisodeId) ?: dramaRepository.getEpisodeForProject(projectId)
        } else {
            dramaRepository.getEpisodeForProject(projectId)
        }
    }

    private suspend fun getCurrentEpisodeStoryboards(): List<StoryboardShot> {
        return if (currentEpisodeId > 0L) {
            getStoryboardsUseCase.execute(projectId, currentEpisodeId)
        } else {
            emptyList()
        }
    }

    private suspend fun checkGenerationPreflight(stage: String): GenerationPreflight {
        val requiresApiKey = stage != GenerationWorker.STAGE_FINAL_VIDEO
        if (requiresApiKey && settingsStore.load().apiKey.isBlank()) {
            return GenerationPreflight.Blocked(R.string.project_generation_missing_api_key)
        }

        val project = getProjectDetailUseCase.execute(projectId)
            ?: return GenerationPreflight.Blocked(R.string.project_missing)
        val episode = currentEpisode()
        val storyboards = getCurrentEpisodeStoryboards()

        return when (stage) {
            GenerationWorker.STAGE_REWRITE -> {
                if (episode?.content.isNullOrBlank()) {
                    GenerationPreflight.Blocked(R.string.project_rewrite_no_content)
                } else {
                    GenerationPreflight.Ready
                }
            }
            GenerationWorker.STAGE_STORYBOARD -> {
                val hasScript = !episode?.scriptContent.isNullOrBlank() || !project.generatedScript.isNullOrBlank()
                if (!hasScript) {
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
            GenerationWorker.STAGE_CHARACTER_EXTRACT -> {
                val hasScript = !episode?.scriptContent.isNullOrBlank() || !project.generatedScript.isNullOrBlank()
                if (!hasScript) {
                    GenerationPreflight.Blocked(R.string.project_generation_missing_script)
                } else {
                    GenerationPreflight.Ready
                }
            }
            GenerationWorker.STAGE_CHARACTER_IMAGE -> {
                val characters = getCharactersUseCase.execute(projectId)
                if (characters.isEmpty()) {
                    GenerationPreflight.Blocked(R.string.project_no_characters)
                } else {
                    GenerationPreflight.Ready
                }
            }
            else -> GenerationPreflight.Ready
        }
    }

    private fun cancelGeneration() {
        if (currentEpisodeId > 0L) {
            GenerationWorker.cancelEpisode(this, projectId, currentEpisodeId)
        } else {
            GenerationWorker.cancelEpisode(this, projectId, 0L)
        }
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
                .putExtra(VideoPlayerActivity.EXTRA_EPISODE_ID, currentEpisodeId)
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
                .putExtra(VideoPlayerActivity.EXTRA_PROJECT_TITLE, projectTitle)
                .putExtra(VideoPlayerActivity.EXTRA_PROJECT_ID, projectId)
                .putExtra(VideoPlayerActivity.EXTRA_EPISODE_ID, currentEpisodeId)
        )
    }

    private fun openScriptViewer() {
        startActivity(
            Intent(this, ScriptViewerActivity::class.java)
                .putExtra(ScriptViewerActivity.EXTRA_PROJECT_ID, projectId)
                .putExtra(ScriptViewerActivity.EXTRA_EPISODE_ID, currentEpisodeId)
        )
    }

    private fun openStoryboardViewer() {
        startActivity(
            Intent(this, StoryboardViewerActivity::class.java)
                .putExtra(StoryboardViewerActivity.EXTRA_PROJECT_ID, projectId)
                .putExtra(StoryboardViewerActivity.EXTRA_EPISODE_ID, currentEpisodeId)
        )
    }

    private fun openImageGallery() {
        startActivity(
            Intent(this, ImageGalleryActivity::class.java)
                .putExtra(ImageGalleryActivity.EXTRA_PROJECT_ID, projectId)
                .putExtra(ImageGalleryActivity.EXTRA_EPISODE_ID, currentEpisodeId)
        )
    }

    private fun openCharacterList() {
        if (cachedCharacterCount <= 0) {
            Toast.makeText(this, R.string.project_no_characters, Toast.LENGTH_SHORT).show()
            return
        }
        startActivity(
            Intent(this, CharacterListActivity::class.java)
                .putExtra(CharacterListActivity.EXTRA_PROJECT_ID, projectId)
        )
    }

    private fun openApiLog() {
        startActivity(Intent(this, ApiLogActivity::class.java))
    }

    private fun confirmRewrite() {
        if (hasActiveGenerationWork) {
            Toast.makeText(this, R.string.project_generation_running, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val episode = currentEpisode()
            if (episode?.content.isNullOrBlank()) {
                Toast.makeText(this@ProjectDetailActivity, R.string.project_rewrite_no_content, Toast.LENGTH_SHORT).show()
                return@launch
            }
            if (!episode?.scriptContent.isNullOrBlank()) {
                AlertDialog.Builder(this@ProjectDetailActivity)
                    .setTitle(R.string.project_regenerate_title)
                    .setMessage(R.string.project_regenerate_rewrite_message)
                    .setNegativeButton(R.string.project_regenerate_cancel, null)
                    .setPositiveButton(R.string.project_regenerate_confirm) { _, _ ->
                        enqueueRewrite()
                    }
                    .show()
            } else {
                enqueueRewrite()
            }
        }
    }

    private fun enqueueRewrite() {
        if (currentEpisodeId <= 0L) {
            Toast.makeText(this, R.string.project_missing, Toast.LENGTH_SHORT).show()
            return
        }
        GenerationWorker.enqueue(this, projectId, currentEpisodeId, GenerationWorker.STAGE_REWRITE)
        Toast.makeText(this, R.string.project_rewrite_queued, Toast.LENGTH_SHORT).show()
        loadProject(projectId)
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
        lifecycleScope.launch {
            dramaRepository.getEpisodes(projectId).forEach {
                GenerationWorker.cancelEpisode(this@ProjectDetailActivity, projectId, it.id)
            }
            val deleted = dramaRepository.deleteProject(projectId)
            if (deleted) {
                Toast.makeText(this@ProjectDetailActivity, R.string.project_deleted, Toast.LENGTH_SHORT).show()
                finish()
            } else {
                Toast.makeText(this@ProjectDetailActivity, R.string.project_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun bindProject(
        project: DramaProject,
        episode: Episode?,
        storyboards: List<StoryboardShot>,
        characters: List<com.huobao.zdrama.domain.model.Character> = emptyList()
    ) {
        hasGeneratedVideos = storyboards.any { it.hasPlayableVideo() }
        finalVideoLocalPath = episode?.finalVideoLocalPath
        hasFinalVideo = episode?.finalVideoStatus == AssetStatus.COMPLETED && isExistingFile(episode.finalVideoLocalPath)
        binding.playVideosButton.isEnabled = hasGeneratedVideos
        binding.playFinalVideoButton.isEnabled = hasFinalVideo
        binding.viewScriptButton.isEnabled = !episode?.scriptContent.isNullOrBlank()
        binding.viewStoryboardButton.isEnabled = storyboards.isNotEmpty()
        binding.viewImagesButton.isEnabled = storyboards.any {
            isExistingFile(it.imageLocalPath) || !it.imageUrl.isNullOrBlank()
        }
        binding.viewCharactersButton.isEnabled = characters.isNotEmpty()
        bindGenerationButtonTexts(project, episode, storyboards, characters)
        binding.titleText.text = project.title
        projectTitle = project.title
        binding.statusText.text = getString(R.string.project_status_label) + "：${project.status.toDisplayText()}\n" +
            getString(R.string.project_stage_label) + "：${project.currentStage.toDisplayText()}"
        bindProgressCard(project, storyboards, characters)
        bindPrompt(project.prompt)
        binding.metaText.text = buildString {
            append(getString(R.string.project_style_label)).append("：").append(project.style).append('\n')
            append(getString(R.string.project_audience_label)).append("：").append(project.targetAudience).append('\n')
            append(getString(R.string.project_aspect_ratio_label)).append("：").append(project.aspectRatio).append('\n')
            append(getString(R.string.project_shot_count_label)).append("：").append(project.shotCount).append('\n')
            append(getString(R.string.project_duration_label)).append("：").append(project.shotDurationSeconds).append('\n')
            append(getString(R.string.project_final_video_status_label)).append("：")
                .append((episode?.finalVideoStatus ?: AssetStatus.PENDING).toDisplayText())
            episode?.finalVideoLocalPath?.takeIf { it.isNotBlank() }?.let { path ->
                append('\n').append(getString(R.string.project_final_video_local_path_label)).append("：").append(path)
            }
            episode?.finalVideoErrorMessage?.takeIf { it.isNotBlank() }?.let { error ->
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

    private fun bindGenerationButtonTexts(
        project: DramaProject,
        episode: Episode?,
        storyboards: List<StoryboardShot>,
        characters: List<com.huobao.zdrama.domain.model.Character> = emptyList()
    ) {
        binding.generateFullButton.setText(
            if (hasAnyGeneratedContent(project, episode, storyboards)) R.string.project_regenerate_full else R.string.project_generate_full
        )
        binding.generateScriptButton.setText(
            if (!episode?.scriptContent.isNullOrBlank()) R.string.project_regenerate_script else R.string.project_generate_script
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
            if (episode?.finalVideoStatus == AssetStatus.COMPLETED || isExistingFile(episode?.finalVideoLocalPath)) {
                R.string.project_recompose_final_video
            } else {
                R.string.project_compose_final_video
            }
        )
        binding.generateCharactersButton.setText(
            if (characters.isNotEmpty()) R.string.project_regenerate_characters else R.string.project_extract_characters
        )
        binding.generateCharacterImagesButton.setText(
            if (characters.any { isExistingFile(it.imageLocalPath) }) {
                R.string.project_regenerate_character_images
            } else {
                R.string.project_generate_character_images
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

    // ────────────── 阶段进度卡片（模仿鸿蒙 1e91bc1） ──────────────
    //
    // 只在后台生成进行中 / 失败时显示。布局：
    //   ● 阶段名                              第 N/M 张
    //   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔  (4dp 进度条)
    //   正在处理：分镜 #3
    //
    // - 只有 IMAGE/VIDEO/CHARACTER_IMAGE 三个阶段有 current/total + entity；
    //   其余阶段（脚本/分镜/角色提取/成片）只显示阶段名 + busyLabel。

    private fun bindProgressCard(
        project: DramaProject,
        storyboards: List<StoryboardShot>,
        characters: List<com.huobao.zdrama.domain.model.Character> = emptyList()
    ) {
        if (!hasActiveGenerationWork) {
            binding.progressCard.visibility = View.GONE
            return
        }
        // 从当前活跃的 workName 反推 stage（REWRITE 在 GenerationStage 里没对应值）
        val activeStage = activeStageFromWorkNames() ?: project.currentStage.name
        val stageLabelRes = stageLabelRes(activeStage)
        binding.progressStageLabel.text = getString(stageLabelRes)

        val progress = collectProgress(activeStage, storyboards, characters)
        if (progress != null && progress.total > 0) {
            // 有 current/total：显示 counter + 进度条 + 正在处理 X
            binding.progressCounter.visibility = View.VISIBLE
            binding.progressCounter.text = getString(
                R.string.project_progress_counter,
                progress.current,
                progress.total
            )
            binding.progressBar.visibility = View.VISIBLE
            binding.progressBar.max = progress.total
            binding.progressBar.progress = progress.current
            binding.progressDetail.visibility = View.VISIBLE
            binding.progressDetail.text = if (progress.entityLabel != null) {
                getString(R.string.project_progress_processing, progress.entityLabel)
            } else {
                getString(R.string.project_generation_waiting_next_shot)
            }
        } else {
            // 无 per-entity 进度：只显示 busyLabel
            binding.progressCounter.visibility = View.GONE
            binding.progressBar.visibility = View.GONE
            binding.progressDetail.visibility = View.VISIBLE
            binding.progressDetail.text = getString(
                R.string.project_generation_running_stage,
                project.currentStage.toDisplayText()
            )
        }
        binding.progressCard.visibility = View.VISIBLE
    }

    /**
     * 从当前活跃的 workName 列表中解析出 stage 字符串（"text" / "rewrite" / "storyboard" / 等）。
     * GenerationStage 枚举不含 REWRITE，所以需要走 workName 反查。返回 null 表示无活跃任务。
     */
    private fun activeStageFromWorkNames(): String? {
        if (currentEpisodeId <= 0L) return null
        val prefix = "generation-$projectId-$currentEpisodeId-"
        generationWorkInfosByName.forEach { (name, infos) ->
            if (!name.startsWith(prefix)) return@forEach
            val isActive = infos.any { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING }
            if (isActive) return name.removePrefix(prefix)
        }
        return null
    }

    private data class ProgressInfo(
        val current: Int,
        val total: Int,
        val entityLabel: String?
    )

    private fun collectProgress(
        stage: String,
        storyboards: List<StoryboardShot>,
        characters: List<com.huobao.zdrama.domain.model.Character>
    ): ProgressInfo? {
        return when (stage) {
            GenerationWorker.STAGE_IMAGE -> mediaProgress(storyboards, { it.imageStatus }, entityShot = true)
            GenerationWorker.STAGE_VIDEO -> mediaProgress(storyboards, { it.videoStatus }, entityShot = true)
            GenerationWorker.STAGE_CHARACTER_IMAGE -> characterImageProgress(characters)
            else -> null
        }
    }

    private fun mediaProgress(
        storyboards: List<StoryboardShot>,
        statusOf: (StoryboardShot) -> AssetStatus,
        entityShot: Boolean
    ): ProgressInfo? {
        if (storyboards.isEmpty()) return null
        val total = storyboards.size
        val current = storyboards.count { statusOf(it) == AssetStatus.COMPLETED } +
            storyboards.count { statusOf(it) == AssetStatus.FAILED }
        val processing = storyboards.firstOrNull { statusOf(it) == AssetStatus.PROCESSING }
        val entity = processing?.let {
            if (entityShot) getString(R.string.project_progress_entity_shot, it.shotNumber) else null
        }
        return ProgressInfo(current = current.coerceAtMost(total), total = total, entityLabel = entity)
    }

    private fun characterImageProgress(characters: List<com.huobao.zdrama.domain.model.Character>): ProgressInfo? {
        if (characters.isEmpty()) return null
        val total = characters.size
        val current = characters.count { it.imageStatus == AssetStatus.COMPLETED } +
            characters.count { it.imageStatus == AssetStatus.FAILED }
        val processing = characters.firstOrNull { it.imageStatus == AssetStatus.PROCESSING }
        // 角色没有 shotNumber 概念，用列表 index + 1 替代（与 Harmony 端 `角色 #${shotNumber}` 一致）
        val entity = processing?.let { idx ->
            val pos = characters.indexOfFirst { it.id == idx.id } + 1
            getString(R.string.project_progress_entity_character, pos)
        }
        return ProgressInfo(current = current.coerceAtMost(total), total = total, entityLabel = entity)
    }

    private fun stageLabelRes(stage: String): Int = when (stage) {
        GenerationWorker.STAGE_TEXT -> R.string.project_progress_stage_text
        GenerationWorker.STAGE_REWRITE -> R.string.project_progress_stage_rewrite
        GenerationWorker.STAGE_STORYBOARD -> R.string.project_progress_stage_storyboard
        GenerationWorker.STAGE_IMAGE -> R.string.project_progress_stage_image
        GenerationWorker.STAGE_VIDEO -> R.string.project_progress_stage_video
        GenerationWorker.STAGE_FINAL_VIDEO -> R.string.project_progress_stage_final_video
        GenerationWorker.STAGE_CHARACTER_EXTRACT -> R.string.project_progress_stage_character_extract
        GenerationWorker.STAGE_CHARACTER_IMAGE -> R.string.project_progress_stage_character_image
        GenerationWorker.STAGE_FULL -> R.string.project_progress_stage_full
        else -> R.string.project_progress_stage_text
    }

    private fun showMissingProject() {
        Toast.makeText(this, R.string.project_missing, Toast.LENGTH_SHORT).show()
        finish()
    }

    // ────────────── 集切换器（横向 chips：第 N 集 / ＋新增；长按删除） ──────────────

    private fun bindEpisodeChips(loadedEpisodes: List<Episode>) {
        binding.episodeChipContainer.removeAllViews()
        loadedEpisodes.forEach { episode ->
            binding.episodeChipContainer.addView(buildEpisodeChip(episode))
        }
        binding.episodeChipContainer.addView(buildAddEpisodeChip())
    }

    private fun buildEpisodeChip(episode: Episode): TextView {
        val selected = episode.id == currentEpisodeId
        return TextView(this).apply {
            text = getString(R.string.episode_chip_format, episode.episodeNumber)
            setTextColor(getColor(if (selected) R.color.zdrama_black else R.color.zdrama_primary))
            setBackgroundColor(getColor(if (selected) R.color.zdrama_primary else R.color.zdrama_surface))
            textSize = 15f
            setPadding(28, 14, 28, 14)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginEnd = 10 }
            setOnClickListener {
                if (episode.id != currentEpisodeId) {
                    currentEpisodeId = episode.id
                    loadProject(projectId)
                }
            }
            setOnLongClickListener {
                confirmDeleteEpisode(episode)
                true
            }
        }
    }

    private fun buildAddEpisodeChip(): TextView {
        return TextView(this).apply {
            text = getString(R.string.episode_add)
            setTextColor(getColor(R.color.zdrama_primary))
            setBackgroundColor(getColor(R.color.zdrama_surface))
            textSize = 15f
            setTypeface(null, android.graphics.Typeface.BOLD)
            setPadding(28, 14, 28, 14)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setOnClickListener { showAddEpisodeDialog() }
        }
    }

    private fun showAddEpisodeDialog() {
        val titleInput = EditText(this).apply { hint = getString(R.string.episode_title_hint) }
        val contentInput = EditText(this).apply {
            hint = getString(R.string.episode_content_hint)
            gravity = Gravity.TOP
            minLines = 4
        }
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 8, 28, 0)
            addView(titleInput)
            addView(contentInput)
        }
        AlertDialog.Builder(this)
            .setTitle(R.string.episode_add_title)
            .setView(container)
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.episode_add_confirm) { _, _ -> createEpisode(titleInput, contentInput) }
            .show()
    }

    private fun createEpisode(titleInput: EditText, contentInput: EditText) {
        val title = titleInput.text?.toString()?.trim().orEmpty()
        val content = contentInput.text?.toString()?.trim()
        if (title.isEmpty() && content.isNullOrBlank()) {
            Toast.makeText(this, R.string.episode_create_failed, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val id = dramaRepository.createEpisodeForProject(projectId, title, content)
            if (id > 0L) {
                currentEpisodeId = id
                Toast.makeText(this@ProjectDetailActivity, R.string.episode_created, Toast.LENGTH_SHORT).show()
                loadProject(projectId)
            } else {
                Toast.makeText(this@ProjectDetailActivity, R.string.episode_create_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun confirmDeleteEpisode(episode: Episode) {
        if (episodes.size <= 1) {
            Toast.makeText(this, R.string.episode_delete_last, Toast.LENGTH_SHORT).show()
            return
        }
        AlertDialog.Builder(this)
            .setTitle(R.string.episode_delete_title)
            .setMessage(getString(
                R.string.episode_delete_message,
                getString(R.string.episode_chip_format, episode.episodeNumber)
            ))
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> deleteEpisode(episode) }
            .show()
    }

    private fun deleteEpisode(episode: Episode) {
        lifecycleScope.launch {
            GenerationWorker.cancelEpisode(this@ProjectDetailActivity, projectId, episode.id)
            val deleted = dramaRepository.deleteEpisode(episode.id)
            if (deleted) {
                currentEpisodeId = 0L // loadProject 重新选定第一集
                Toast.makeText(this@ProjectDetailActivity, R.string.episode_deleted, Toast.LENGTH_SHORT).show()
                loadProject(projectId)
            } else {
                Toast.makeText(this@ProjectDetailActivity, R.string.episode_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
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
