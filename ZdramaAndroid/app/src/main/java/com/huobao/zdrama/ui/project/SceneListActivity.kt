package com.huobao.zdrama.ui.project

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivitySceneListBinding
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetScenesUseCase
import kotlinx.coroutines.launch

class SceneListActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySceneListBinding
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getScenesUseCase: GetScenesUseCase
    private val adapter = SceneAdapter()
    private var projectId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySceneListBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val dramaRepository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(dramaRepository)
        getScenesUseCase = GetScenesUseCase(dramaRepository)

        binding.sceneList.layoutManager = LinearLayoutManager(this)
        binding.sceneList.adapter = adapter

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        if (projectId <= 0L) {
            Toast.makeText(this, R.string.project_missing, Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        loadScenes()
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadScenes()
    }

    private fun loadScenes() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                Toast.makeText(this@SceneListActivity, R.string.project_missing, Toast.LENGTH_SHORT).show()
                finish()
                return@launch
            }
            val scenes = getScenesUseCase.execute(projectId)
            binding.titleText.text = project.title
            binding.countText.text = getString(R.string.project_scene_count_label, scenes.size)
            adapter.submit(scenes)
            binding.emptyText.visibility = if (scenes.isEmpty()) View.VISIBLE else View.GONE
            binding.sceneList.visibility = if (scenes.isEmpty()) View.GONE else View.VISIBLE
        }
    }

    companion object {
        const val EXTRA_PROJECT_ID = "project_id"
    }
}
