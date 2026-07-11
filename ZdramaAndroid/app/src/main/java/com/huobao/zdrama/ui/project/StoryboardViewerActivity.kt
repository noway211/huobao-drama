package com.huobao.zdrama.ui.project

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityStoryboardViewerBinding
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import kotlinx.coroutines.launch

class StoryboardViewerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityStoryboardViewerBinding
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private var projectId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityStoryboardViewerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val repository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(repository)
        getStoryboardsUseCase = GetStoryboardsUseCase(repository)

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        if (projectId <= 0L) {
            finishWithMessage(R.string.project_missing)
            return
        }
        loadStoryboards()
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadStoryboards()
    }

    private fun loadStoryboards() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                finishWithMessage(R.string.project_missing)
                return@launch
            }
            val storyboards = getStoryboardsUseCase.execute(projectId)
            if (storyboards.isEmpty()) {
                finishWithMessage(R.string.project_no_storyboards)
                return@launch
            }
            binding.titleText.text = project.title
            binding.storyboardText.text =
                StoryboardTextFormatter.format(this@StoryboardViewerActivity, storyboards)
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
