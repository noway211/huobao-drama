package com.huobao.zdrama.ui.project

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityScriptViewerBinding
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import kotlinx.coroutines.launch

class ScriptViewerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityScriptViewerBinding
    private lateinit var dramaRepository: DramaRepository
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private var projectId: Long = 0L
    private var episodeId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityScriptViewerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        dramaRepository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(dramaRepository)
        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        episodeId = intent.getLongExtra(EXTRA_EPISODE_ID, 0L)
        if (projectId <= 0L) {
            finishWithMessage(R.string.project_missing)
            return
        }
        loadScript()
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadScript()
    }

    private fun loadScript() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                finishWithMessage(R.string.project_missing)
                return@launch
            }
            val episode = if (episodeId > 0L) {
                dramaRepository.getEpisodeById(episodeId)
            } else {
                dramaRepository.getEpisodeForProject(projectId)
            }
            val script = episode?.scriptContent.orEmpty()
            if (script.isBlank()) {
                finishWithMessage(R.string.project_no_script)
                return@launch
            }
            binding.titleText.text = getString(
                    R.string.episode_chip_format,
                    episode?.episodeNumber ?: 0
                ) + " · " + project.title
            binding.scriptText.text = script
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
