package com.huobao.zdrama.ui.project

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityImageGalleryBinding
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import kotlinx.coroutines.launch

class ImageGalleryActivity : AppCompatActivity() {
    private lateinit var binding: ActivityImageGalleryBinding
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private lateinit var repository: DramaRepository
    private val adapter = ImageGalleryAdapter(
        onLongClick = { shot -> confirmDeleteOne(shot) },
        onDeleteImage = { shot -> confirmDeleteOne(shot) }
    )
    private var projectId: Long = 0L
    private var episodeId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityImageGalleryBinding.inflate(layoutInflater)
        setContentView(binding.root)

        repository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(repository)
        getStoryboardsUseCase = GetStoryboardsUseCase(repository)

        binding.imageList.layoutManager = LinearLayoutManager(this)
        binding.imageList.adapter = adapter
        binding.deleteAllButton.setOnClickListener { confirmDeleteAll() }

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        episodeId = intent.getLongExtra(EXTRA_EPISODE_ID, 0L)
        if (projectId <= 0L) {
            finishWithMessage(R.string.project_missing)
            return
        }
        loadImages()
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadImages()
    }

    private suspend fun currentEpisodeStoryboards(): List<StoryboardShot> {
        return if (episodeId > 0L) {
            getStoryboardsUseCase.execute(projectId, episodeId)
        } else {
            getStoryboardsUseCase.execute(projectId)
        }
    }

    private fun loadImages() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                finishWithMessage(R.string.project_missing)
                return@launch
            }
            val storyboards = currentEpisodeStoryboards()
            val imageCount = storyboards.count {
                !it.imageLocalPath.isNullOrBlank() || !it.imageUrl.isNullOrBlank()
            }
            if (storyboards.isEmpty() || imageCount == 0) {
                finishWithMessage(R.string.project_no_images)
                return@launch
            }
            binding.titleText.text = project.title
            binding.countText.text = getString(
                R.string.project_image_count_summary,
                imageCount,
                storyboards.size
            )
            adapter.submitList(storyboards)
            binding.deleteAllButton.isEnabled = true
        }
    }

    // ────────────── 删除操作 ──────────────

    private fun confirmDeleteOne(shot: StoryboardShot) {
        AlertDialog.Builder(this)
            .setTitle(R.string.project_image_delete_title)
            .setMessage(R.string.project_image_delete_message)
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> performDeleteOne(shot.id) }
            .show()
    }

    private fun performDeleteOne(shotId: Long) {
        lifecycleScope.launch {
            val result = repository.deleteShotImage(shotId)
            if (result.dbUpdated) {
                Toast.makeText(this@ImageGalleryActivity, R.string.project_image_deleted, Toast.LENGTH_SHORT).show()
                loadImages()
            } else {
                Toast.makeText(this@ImageGalleryActivity, R.string.project_image_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun confirmDeleteAll() {
        lifecycleScope.launch {
            val shots = currentEpisodeStoryboards()
                .filter { !it.imageLocalPath.isNullOrBlank() || !it.imageUrl.isNullOrBlank() }
            if (shots.isEmpty()) {
                Toast.makeText(this@ImageGalleryActivity, R.string.project_no_images, Toast.LENGTH_SHORT).show()
                return@launch
            }
            AlertDialog.Builder(this@ImageGalleryActivity)
                .setTitle(R.string.project_image_delete_all)
                .setMessage(getString(R.string.project_image_bulk_delete_confirm_message, shots.size))
                .setNegativeButton(R.string.project_delete_cancel, null)
                .setPositiveButton(R.string.project_delete_confirm) { _, _ -> performDeleteAll() }
                .show()
        }
    }

    private fun performDeleteAll() {
        lifecycleScope.launch {
            val count = repository.deleteAllStoryboardImages(projectId, episodeId)
            Toast.makeText(
                this@ImageGalleryActivity,
                getString(R.string.project_image_bulk_deleted, count),
                Toast.LENGTH_SHORT
            ).show()
            loadImages()
        }
    }

    private fun finishWithMessage(messageRes: Int) {
        Toast.makeText(this, messageRes, Toast.LENGTH_SHORT).show()
        finish()
    }

    companion object {
        const val EXTRA_PROJECT_ID = "extra_project_id"
        const val EXTRA_EPISODE_ID = "extra_episode_id"
    }
}
