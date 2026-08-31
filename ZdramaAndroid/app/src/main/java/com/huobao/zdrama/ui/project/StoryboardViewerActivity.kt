package com.huobao.zdrama.ui.project

import android.app.AlertDialog
import android.os.Bundle
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityStoryboardViewerBinding
import com.huobao.zdrama.domain.model.Character
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetCharactersUseCase
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import com.huobao.zdrama.domain.usecase.UpdateShotPromptUseCase
import kotlinx.coroutines.launch
import java.util.ArrayList

class StoryboardViewerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityStoryboardViewerBinding
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private lateinit var getCharactersUseCase: GetCharactersUseCase
    private lateinit var updateShotPromptUseCase: UpdateShotPromptUseCase
    private lateinit var dramaRepository: DramaRepository
    private val gson = Gson()
    private var projectId: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityStoryboardViewerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val repository = DramaRepository(this)
        dramaRepository = repository
        getProjectDetailUseCase = GetProjectDetailUseCase(repository)
        getStoryboardsUseCase = GetStoryboardsUseCase(repository)
        getCharactersUseCase = GetCharactersUseCase(repository)
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
            val characters = getCharactersUseCase.execute(projectId)
            binding.shotCountText.text = getString(R.string.project_shots_summary, all.size)
            binding.cardContainer.removeAllViews()
            for (s in all) {
                binding.cardContainer.addView(buildShotCard(s, characters))
            }
        }
    }

    private fun buildShotCard(s: StoryboardShot, characters: List<Character>): LinearLayout {
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
        // 角色绑定（characterIds 解析展示，可点击「编辑」重新绑定）
        card.addView(buildBindingBlock(s, characters))
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

    /**
     * 角色绑定块：标题行（角色 · N 个 · 编辑）+ 绑定内容行。
     * characterIds 兼容数字 ID 数组（用户绑定）与名字数组（LLM 初始生成）。
     */
    private fun buildBindingBlock(shot: StoryboardShot, characters: List<Character>): LinearLayout {
        val block = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = 10 }
            orientation = LinearLayout.VERTICAL
            setPadding(12, 12, 12, 12)
            setBackgroundColor(getColor(R.color.zdrama_black))
        }

        val bound = resolveBoundCharacters(shot, characters)

        // 标题行：角色 | N 个 | 编辑
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = 6 }
        }
        header.addView(TextView(this).apply {
            text = "角色"
            setTextColor(getColor(R.color.zdrama_text_secondary))
            textSize = 13f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        header.addView(TextView(this).apply {
            text = "${bound.size} 个"
            setTextColor(getColor(R.color.zdrama_text_secondary))
            textSize = 12f
            setPadding(0, 0, 8, 0)
        })
        header.addView(TextView(this).apply {
            text = "编辑"
            setTextColor(getColor(R.color.zdrama_primary))
            textSize = 12f
            setOnClickListener { showBindingEditor(shot, characters) }
        })
        block.addView(header)

        block.addView(TextView(this).apply {
            text = bindingContentText(shot, bound)
            setTextColor(getColor(R.color.zdrama_text_secondary))
            textSize = 13f
        })

        return block
    }

    /** 绑定内容文本：未绑定 / 名字列表（最多 3 个 + 溢出数）/ 绑定已失效。 */
    private fun bindingContentText(shot: StoryboardShot, bound: List<Character>): String {
        if (shot.characterIds.isNullOrBlank()) return "未绑定角色"
        if (bound.isEmpty()) return "绑定已失效，请重新编辑"
        val shown = bound.take(3).joinToString("    ") { "🎭 ${it.name}" }
        val overflow = if (bound.size > 3) "    +${bound.size - 3}" else ""
        return shown + overflow
    }

    /** 解析绑定：优先数字 ID 查表，回退名字查表（与生成图 UseCase 同语义）。 */
    private fun resolveBoundCharacters(shot: StoryboardShot, characters: List<Character>): List<Character> {
        if (shot.characterIds.isNullOrBlank() || characters.isEmpty()) return emptyList()

        val ids = parseBoundIds(shot.characterIds)
        if (ids.isNotEmpty()) {
            val charMap = characters.associateBy { it.id }
            val out = ids.mapNotNull { charMap[it] }
            if (out.isNotEmpty()) return out
        }

        val names = parseBoundNames(shot.characterIds) ?: return emptyList()
        val nameMap = characters.associateBy { it.name }
        return names.mapNotNull { nameMap[it] }
    }

    private fun parseBoundIds(characterIds: String): List<Long> {
        val type = object : TypeToken<ArrayList<Long>>() {}.type
        return runCatching { gson.fromJson<ArrayList<Long>>(characterIds, type) }
            .getOrNull()?.toList() ?: emptyList()
    }

    private fun parseBoundNames(characterIds: String): List<String>? {
        val type = object : TypeToken<ArrayList<String>>() {}.type
        return runCatching { gson.fromJson<ArrayList<String>>(characterIds, type) }
            .getOrNull()?.toList()
    }

    /** 角色绑定编辑对话框：多选角色，保存后写回 characterIds（空选写空串）。 */
    private fun showBindingEditor(shot: StoryboardShot, characters: List<Character>) {
        if (characters.isEmpty()) {
            Toast.makeText(this, "请先在项目详情提取角色", Toast.LENGTH_SHORT).show()
            return
        }
        val names = characters.map { it.name }.toTypedArray()
        val boundIds = resolveBoundCharacters(shot, characters).map { it.id }.toSet()
        val checked = BooleanArray(names.size) { index -> characters[index].id in boundIds }

        AlertDialog.Builder(this)
            .setTitle("编辑 #${shot.shotNumber} 角色绑定")
            .setMultiChoiceItems(names, checked) { _, which, isChecked ->
                checked[which] = isChecked
            }
            .setPositiveButton("保存") { _, _ ->
                val ids = characters.filterIndexed { index, _ -> checked[index] }
                    .map { it.id }.sorted()
                saveBindingAndReload(shot, ids)
            }
            .setNegativeButton("取消", null)
            .show()
    }

    /** 保存绑定并刷新列表。 */
    private fun saveBindingAndReload(shot: StoryboardShot, ids: List<Long>) {
        lifecycleScope.launch {
            val json = if (ids.isEmpty()) "" else gson.toJson(ids)
            val ok = dramaRepository.updateShotCharacterIds(shot.id, json)
            Toast.makeText(
                this@StoryboardViewerActivity,
                if (ok) "#${shot.shotNumber} 角色绑定已更新" else "角色绑定保存失败，请重试",
                Toast.LENGTH_SHORT
            ).show()
            if (ok) loadStoryboards()
        }
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