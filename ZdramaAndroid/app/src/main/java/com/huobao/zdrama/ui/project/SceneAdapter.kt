package com.huobao.zdrama.ui.project

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.huobao.zdrama.R
import com.huobao.zdrama.databinding.ItemSceneBinding
import com.huobao.zdrama.domain.model.Scene

class SceneAdapter : RecyclerView.Adapter<SceneAdapter.SceneViewHolder>() {
    private val scenes = mutableListOf<Scene>()

    fun submit(items: List<Scene>) {
        scenes.clear()
        scenes.addAll(items)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SceneViewHolder {
        val binding = ItemSceneBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return SceneViewHolder(binding)
    }

    override fun onBindViewHolder(holder: SceneViewHolder, position: Int) {
        holder.bind(scenes[position])
    }

    override fun getItemCount(): Int = scenes.size

    class SceneViewHolder(
        private val binding: ItemSceneBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(scene: Scene) {
            val context = binding.root.context
            binding.locationText.text = scene.location
            binding.timeText.text = scene.time.ifBlank { context.getString(R.string.project_scene_time_empty) }
            binding.atmosphereText.text = scene.atmosphere.ifBlank {
                context.getString(R.string.project_scene_atmosphere_empty)
            }
            binding.promptText.text = scene.prompt.ifBlank { context.getString(R.string.project_scene_prompt_empty) }
        }
    }
}
