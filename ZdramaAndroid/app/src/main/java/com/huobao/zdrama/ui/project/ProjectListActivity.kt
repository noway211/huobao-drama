package com.huobao.zdrama.ui.project

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityProjectListBinding
import com.huobao.zdrama.domain.usecase.GetProjectsUseCase
import kotlinx.coroutines.launch

class ProjectListActivity : AppCompatActivity() {
    private lateinit var binding: ActivityProjectListBinding
    private lateinit var getProjectsUseCase: GetProjectsUseCase
    private val adapter = ProjectAdapter { project ->
        startActivity(
            Intent(this, ProjectDetailActivity::class.java)
                .putExtra(ProjectDetailActivity.EXTRA_PROJECT_ID, project.id)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProjectListBinding.inflate(layoutInflater)
        setContentView(binding.root)

        getProjectsUseCase = GetProjectsUseCase(DramaRepository(this))
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
}
