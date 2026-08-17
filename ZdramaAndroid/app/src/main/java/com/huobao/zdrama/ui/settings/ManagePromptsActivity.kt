package com.huobao.zdrama.ui.settings

import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.huobao.zdrama.R
import com.huobao.zdrama.data.prompt.PromptDefaults
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.databinding.ActivityManagePromptsBinding

/**
 * 管理 4 个 LLM 流程的自定义系统提示词。
 * 移植自 Harmony 端 SettingsPage 的"管理提示词" Modal (commit 8c12702)。
 *
 * 设计：
 * - 顶部下拉框 (Spinner) 切换 4 个流程（脚本创作/脚本改写/角色提取/分镜拆解）
 * - 中部多行 TextInputEditText 编辑当前 prompt
 * - 底部 [重置为默认] [保存当前] 按钮独立作用于当前 prompt
 * - 状态栏显示该 prompt 是否已自定义（"使用默认值" vs "已自定义"）
 */
class ManagePromptsActivity : AppCompatActivity() {
    private lateinit var binding: ActivityManagePromptsBinding
    private lateinit var settingsStore: AgnesSettingsStore
    private var currentSettings: AgnesSettings = AgnesSettings.defaults()
    private var selectedIndex: Int = 0
    // 输入框脏标记：切换 tab 时若已脏，提示未保存
    private var inputDirty: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityManagePromptsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        settingsStore = AgnesSettingsStore(this)
        setupSpinner()
        binding.closeButton.setOnClickListener { finish() }
        binding.resetButton.setOnClickListener { onResetClick() }
        binding.saveButton.setOnClickListener { onSaveClick() }
        binding.promptInput.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                inputDirty = binding.promptInput.text?.toString().orEmpty() != currentValueForSelection()
            }
        }
        // 简单 text watcher：内容变化就置脏
        binding.promptInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                inputDirty = s?.toString().orEmpty() != currentValueForSelection()
                updateStatus()
            }
        })
    }

    override fun onResume() {
        super.onResume()
        currentSettings = settingsStore.load()
        renderForSelection()
    }

    private fun setupSpinner() {
        val labels = listOf(
            getString(R.string.manage_prompts_tab_script_create),
            getString(R.string.manage_prompts_tab_script_rewrite),
            getString(R.string.manage_prompts_tab_character_extract),
            getString(R.string.manage_prompts_tab_storyboard)
        )
        binding.promptSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            labels
        ).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        binding.promptSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                confirmDiscardIfDirty {
                    selectedIndex = position
                    renderForSelection()
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    /**
     * 当前 spinner 选中的流程对应的 (custom 字段 getter / default 常量 getter) 元组。
     * 顺序与 setupSpinner labels 严格一致。
     */
    private data class PromptSlot(
        val name: String,
        val getCustom: (AgnesSettings) -> String?,
        val getDefault: () -> String,
        val setCustom: (AgnesSettings, String?) -> AgnesSettings
    )

    private fun slotFor(index: Int): PromptSlot = when (index) {
        0 -> PromptSlot(
            name = "script_create",
            getCustom = { it.customScriptCreatePrompt },
            getDefault = { PromptDefaults.SCRIPT_CREATE_PROMPT },
            setCustom = { s, v -> s.copy(customScriptCreatePrompt = v) }
        )
        1 -> PromptSlot(
            name = "script_rewrite",
            getCustom = { it.customScriptRewritePrompt },
            getDefault = { PromptDefaults.SCRIPT_REWRITE_PROMPT },
            setCustom = { s, v -> s.copy(customScriptRewritePrompt = v) }
        )
        2 -> PromptSlot(
            name = "character_extract",
            getCustom = { it.customCharacterExtractPrompt },
            getDefault = { PromptDefaults.CHARACTER_EXTRACT_PROMPT },
            setCustom = { s, v -> s.copy(customCharacterExtractPrompt = v) }
        )
        else -> PromptSlot(
            name = "storyboard",
            getCustom = { it.customStoryboardPrompt },
            getDefault = { PromptDefaults.STORYBOARD_PROMPT },
            setCustom = { s, v -> s.copy(customStoryboardPrompt = v) }
        )
    }

    private fun currentValueForSelection(): String {
        val slot = slotFor(selectedIndex)
        return slot.getCustom(currentSettings)?.takeIf { it.isNotBlank() }
            ?: slot.getDefault()
    }

    private fun renderForSelection() {
        val slot = slotFor(selectedIndex)
        val custom = slot.getCustom(currentSettings)
        val displayValue = custom?.takeIf { it.isNotBlank() } ?: slot.getDefault()
        binding.promptInput.setText(displayValue)
        binding.promptInput.setSelection(0)
        inputDirty = false
        updateStatus()
    }

    private fun updateStatus() {
        val slot = slotFor(selectedIndex)
        val custom = slot.getCustom(currentSettings)
        val isCustomized = !custom.isNullOrBlank()
        val baseText = if (isCustomized) {
            getString(R.string.manage_prompts_status_customized)
        } else {
            getString(R.string.manage_prompts_status_default)
        }
        val dirtyText = if (inputDirty) " · ${getString(R.string.manage_prompts_status_unsaved)}" else ""
        binding.statusText.text = baseText + dirtyText
    }

    private fun onResetClick() {
        val slot = slotFor(selectedIndex)
        val newSettings = slot.setCustom(currentSettings, null)
        runCatching { settingsStore.save(newSettings) }
            .onSuccess {
                currentSettings = newSettings
                renderForSelection()
                Toast.makeText(this, R.string.manage_prompts_reset_done, Toast.LENGTH_SHORT).show()
            }
            .onFailure {
                Toast.makeText(this, R.string.manage_prompts_save_failed, Toast.LENGTH_SHORT).show()
            }
    }

    private fun onSaveClick() {
        val slot = slotFor(selectedIndex)
        val text = binding.promptInput.text?.toString().orEmpty()
        val newValue: String? = text.trim().takeIf { it.isNotEmpty() }
        val newSettings = slot.setCustom(currentSettings, newValue)
        runCatching { settingsStore.save(newSettings) }
            .onSuccess {
                currentSettings = newSettings
                inputDirty = false
                updateStatus()
                Toast.makeText(this, R.string.manage_prompts_save_done, Toast.LENGTH_SHORT).show()
            }
            .onFailure {
                Toast.makeText(this, R.string.manage_prompts_save_failed, Toast.LENGTH_SHORT).show()
            }
    }

    /**
     * 切换 spinner 时若当前编辑未保存，弹确认；用户取消则还原 spinner 选中项。
     */
    private fun confirmDiscardIfDirty(onProceed: () -> Unit) {
        if (!inputDirty) {
            onProceed()
            return
        }
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle(R.string.manage_prompts_discard_title)
            .setMessage(R.string.manage_prompts_discard_message)
            .setPositiveButton(R.string.manage_prompts_discard_confirm) { _, _ -> onProceed() }
            .setNegativeButton(R.string.manage_prompts_discard_cancel) { _, _ ->
                binding.promptSpinner.setSelection(selectedIndex)
            }
            .show()
    }
}
