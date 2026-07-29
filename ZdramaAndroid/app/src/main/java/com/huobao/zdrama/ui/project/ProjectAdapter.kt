package com.huobao.zdrama.ui.project

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.huobao.zdrama.R
import com.huobao.zdrama.databinding.ItemProjectBinding
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus

class ProjectAdapter(
    private val onProjectClick: (DramaProject) -> Unit,
    private val onProjectLongClick: (DramaProject) -> Unit = {}
) : RecyclerView.Adapter<ProjectAdapter.ProjectViewHolder>() {
    private val projects = mutableListOf<DramaProject>()

    fun submitList(items: List<DramaProject>) {
        projects.clear()
        projects.addAll(items)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ProjectViewHolder {
        val binding = ItemProjectBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ProjectViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ProjectViewHolder, position: Int) {
        holder.bind(projects[position])
    }

    override fun getItemCount(): Int = projects.size

    inner class ProjectViewHolder(
        private val binding: ItemProjectBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(project: DramaProject) {
            val context = binding.root.context
            binding.titleText.text = project.title
            binding.statusText.text = "${project.status.toDisplayText()} · ${project.currentStage.toDisplayText()} · ${context.getString(R.string.project_shots_summary, project.shotCount)}"
            binding.promptText.text = project.prompt
            binding.root.setOnClickListener { onProjectClick(project) }
            binding.root.setOnLongClickListener {
                onProjectLongClick(project)
                true
            }
        }

        private fun ProjectStatus.toDisplayText(): String {
            val context = binding.root.context
            return context.getString(
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
            val context = binding.root.context
            return context.getString(
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
    }
}
