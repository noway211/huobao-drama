package com.huobao.zdrama.ui.project

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityImageGalleryBinding
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import kotlinx.coroutines.launch

class ImageGalleryActivity : AppCompatActivity() {
    private lateinit var binding: ActivityImageGalleryBinding
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private val adapter = ImageGalleryAdapter()
    private var projectId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityImageGalleryBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val repository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(repository)
        getStoryboardsUseCase = GetStoryboardsUseCase(repository)

        binding.imageList.layoutManager = LinearLayoutManager(this)
        binding.imageList.adapter = adapter

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
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

    private fun loadImages() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                finishWithMessage(R.string.project_missing)
                return@launch
            }
            val storyboards = getStoryboardsUseCase.execute(projectId)
            val hasAnyImage = storyboards.any {
                !it.imageLocalPath.isNullOrBlank() || !it.imageUrl.isNullOrBlank()
            }
            if (storyboards.isEmpty() || !hasAnyImage) {
                finishWithMessage(R.string.project_no_images)
                return@launch
            }
            binding.titleText.text = project.title
            adapter.submitList(storyboards)
        }
    }

    private fun finishWithMessage(messageRes: Int) {
        Toast.makeText(this, messageRes, Toast.LENGTH_SHORT).show()
        finish()
    }

    companion object {
        const val EXTRA_PROJECT_ID = "extra_project_id"
    }
}
