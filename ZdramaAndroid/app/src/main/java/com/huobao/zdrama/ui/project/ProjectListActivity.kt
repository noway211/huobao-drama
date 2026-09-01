package com.huobao.zdrama.ui.project

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityProjectListBinding
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.usecase.GetProjectsUseCase
import com.huobao.zdrama.worker.GenerationWorker
import kotlinx.coroutines.launch

class ProjectListActivity : AppCompatActivity() {
    private lateinit var binding: ActivityProjectListBinding
    private lateinit var dramaRepository: DramaRepository
    private lateinit var getProjectsUseCase: GetProjectsUseCase
    private val adapter = ProjectAdapter(
        onProjectClick = { project ->
            startActivity(
                Intent(this, ProjectDetailActivity::class.java)
                    .putExtra(ProjectDetailActivity.EXTRA_PROJECT_ID, project.id)
            )
        },
        onProjectLongClick = { project -> confirmDeleteProject(project) }
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProjectListBinding.inflate(layoutInflater)
        setContentView(binding.root)

        dramaRepository = DramaRepository(this)
        getProjectsUseCase = GetProjectsUseCase(dramaRepository)
        binding.projectRecyclerView.layoutManager = LinearLayoutManager(this)
        binding.projectRecyclerView.adapter = adapter
    }

    override fun onResume() {
        super.onResume()
        loadProjects()
    }

    private fun loadProjects() {
        lifecycleScope.launch {
            val projects = getProjectsUseCase.execute()
            adapter.submitList(projects)
            binding.emptyText.visibility = if (projects.isEmpty()) View.VISIBLE else View.GONE
        }
    }

    private fun confirmDeleteProject(project: DramaProject) {
        AlertDialog.Builder(this)
            .setTitle(R.string.project_delete_title)
            .setMessage(getString(R.string.project_list_delete_message, project.title))
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> deleteProject(project) }
            .show()
    }

    private fun deleteProject(project: DramaProject) {
        lifecycleScope.launch {
            dramaRepository.getEpisodes(project.id).forEach {
                GenerationWorker.cancelEpisode(this@ProjectListActivity, project.id, it.id)
            }
            val deleted = dramaRepository.deleteProject(project.id)
            if (deleted) {
                Toast.makeText(this@ProjectListActivity, R.string.project_deleted, Toast.LENGTH_SHORT).show()
                loadProjects()
            } else {
                Toast.makeText(this@ProjectListActivity, R.string.project_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }
}
