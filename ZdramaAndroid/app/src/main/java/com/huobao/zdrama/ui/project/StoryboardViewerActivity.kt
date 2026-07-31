package com.huobao.zdrama.ui.project

import android.app.AlertDialog
import android.os.Bundle
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityStoryboardViewerBinding
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import com.huobao.zdrama.domain.usecase.UpdateShotPromptUseCase
import kotlinx.coroutines.launch

class StoryboardViewerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityStoryboardViewerBinding
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private lateinit var updateShotPromptUseCase: UpdateShotPromptUseCase
    private var projectId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityStoryboardViewerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val repository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(repository)
        getStoryboardsUseCase = GetStoryboardsUseCase(repository)
        updateShotPromptUseCase = UpdateShotPromptUseCase(repository)

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        if (projectId <= 0L) {
            Toast.makeText(this, R.string.project_missing, Toast.LENGTH_SHORT).show()
            finish()
            return
        }
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadStoryboards()
    }

    private fun loadStoryboards() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                Toast.makeText(this@StoryboardViewerActivity, R.string.project_missing, Toast.LENGTH_SHORT).show()
                finish()
                return@launch
            }
            val all = getStoryboardsUseCase.execute(projectId)
            if (all.isEmpty()) {
                Toast.makeText(this@StoryboardViewerActivity, R.string.project_no_storyboards, Toast.LENGTH_SHORT).show()
                finish()
                return@launch
            }
            binding.shotCountText.text = getString(R.string.project_shots_summary, all.size)
            binding.cardContainer.removeAllViews()
            for (s in all) {
                binding.cardContainer.addView(buildShotCard(s))
            }
        }
    }

    private fun buildShotCard(s: StoryboardShot): LinearLayout {
        val card = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, 0, 0, 16) }
            orientation = LinearLayout.VERTICAL
            setPadding(16, 16, 16, 16)
            setBackgroundColor(getColor(R.color.zdrama_surface))
        }

        // title
        card.addView(createTitleText(s.shotNumber, s.scene))
        // image prompt
        card.addView(createPromptLabel(
            getString(R.string.project_image_prompt_label),
            s.imagePrompt
        ) { showEditDialog(s.id, s.shotNumber, s.imagePrompt, true) })
        // video prompt
        card.addView(createPromptLabel(
            getString(R.string.project_video_prompt_label),
            s.videoPrompt
        ) { showEditDialog(s.id, s.shotNumber, s.videoPrompt, false) })
        // meta
        card.addView(createMetaLabel(s))

        return card
    }

    private fun createTitleText(num: Int, scene: String): TextView {
        val v = TextView(this)
        v.text = "#$num  $scene"
        v.setTextColor(getColor(R.color.zdrama_text_primary))
        v.textSize = 16f
        v.setTypeface(null, android.graphics.Typeface.BOLD)
        v.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 12 }
        return v
    }

    /** Create a clickable prompt label */
    private fun createPromptLabel(label: String, text: String, onEdit: () -> Unit): LinearLayout {
        val block = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = 10 }
            orientation = LinearLayout.VERTICAL
            setPadding(12, 12, 12, 12)
            setBackgroundColor(getColor(R.color.zdrama_black))
        }

        block.addView(TextView(this).apply {
            setText(label)
            setTextColor(getColor(R.color.zdrama_text_secondary))
            textSize = 13f
        })

        block.addView(TextView(this).apply {
            setText(text)
            setTextColor(getColor(R.color.zdrama_text_primary))
            textSize = 14f
        })

        block.addView(TextView(this).apply {
            setText("点击编辑")
            setTextColor(getColor(R.color.zdrama_primary))
            textSize = 12f
            setPadding(0, 8, 0, 0)
            setOnClickListener { onEdit() }
        })

        return block
    }

    /** Create shot meta block */
    private fun createMetaLabel(shot: StoryboardShot): TextView {
        val meta = StringBuilder()
        meta.append(getString(R.string.project_action_label) + "：${shot.action}\n")
        meta.append(getString(R.string.project_dialogue_label) + "：${shot.dialogue}\n")
        meta.append(getString(R.string.project_camera_label) + "：${shot.camera}\n")
        meta.append("时长：${shot.durationSeconds}s")
        if (!shot.imageErrorMessage.isNullOrEmpty()) {
            meta.append("\n图片错误：${shot.imageErrorMessage}")
        }
        if (!shot.videoErrorMessage.isNullOrEmpty()) {
            meta.append("\n视频错误：${shot.videoErrorMessage}")
        }

        val v = TextView(this).apply {
            setText(meta.toString())
            setTextColor(getColor(R.color.zdrama_text_secondary))
            textSize = 13f
        }
        return v
    }

    /** Show edit alert dialog */
    private fun showEditDialog(shotId: Long, shotNumber: Int, current: String, isImagePrompt: Boolean) {
        val label = if (isImagePrompt) getString(R.string.project_image_prompt_label) else getString(R.string.project_video_prompt_label)
        val input = EditText(this).apply { setText(current) }

        AlertDialog.Builder(this)
            .setTitle("编辑 #$shotNumber $label")
            .setView(input)
            .setPositiveButton("保存") { _, _ ->
                val newText = input.text?.toString()?.trim()
                if (!newText.isNullOrBlank() && newText != current) {
                    savePromptAndReload(shotId, newText, isImagePrompt)
                }
            }
            .setNegativeButton("取消", null)
            .show()
    }

    /** Save the updated prompt and reload */
    private fun savePromptAndReload(shotId: Long, newText: String, isImagePrompt: Boolean) {
        lifecycleScope.launch {
            val ok = if (isImagePrompt) {
                updateShotPromptUseCase.updateImagePrompt(shotId, newText)
            } else {
                updateShotPromptUseCase.updateVideoPrompt(shotId, newText)
            }
            val label = if (isImagePrompt) getString(R.string.project_image_prompt_label) else getString(R.string.project_video_prompt_label)
            Toast.makeText(
                this@StoryboardViewerActivity,
                if (ok) "${label} 已更新" else "${label} 更新失败",
                Toast.LENGTH_SHORT
            ).show()
            if (ok) loadStoryboards()
        }
    }

    companion object {
        const val EXTRA_PROJECT_ID = "extra_project_id"
    }
}