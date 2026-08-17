package com.huobao.zdrama.ui.settings

import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
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
 * UI 结构（与 Harmony 对齐）：
 * - 顶部下拉框切换 3 个 tab：脚本 / 角色提取 / 分镜
 * - "脚本" tab 内含 2 个 TextArea（创作剧本 + 改写剧本），共享 1 组 [重置为默认][保存当前] 按钮
 * - "角色提取" / "分镜" tab 各 1 个 TextArea + 1 组按钮
 * - 每个 TextArea 顶部 hint 显示"默认 N 字"（取自 PromptDefaults 对应常量长度）
 * - 留空保存 → store 端写入 null，下次调用走默认；与 Harmony 端 (customXxx ?? '').trim() || DEFAULT 语义一致
 */
class ManagePromptsActivity : AppCompatActivity() {
    private lateinit var binding: ActivityManagePromptsBinding
    private lateinit var settingsStore: AgnesSettingsStore
    private var currentSettings: AgnesSettings = AgnesSettings.defaults()
    private var activeTab: Int = TAB_SCRIPT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityManagePromptsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        settingsStore = AgnesSettingsStore(this)
        setupSpinner()
        setupHelperTexts()
        setupClickListeners()
    }

    override fun onResume() {
        super.onResume()
        currentSettings = settingsStore.load()
        renderActiveTab()
    }

    // ────────────── 初始化 ──────────────

    private fun setupSpinner() {
        val labels = listOf(
            getString(R.string.manage_prompts_tab_script),
            getString(R.string.manage_prompts_tab_character),
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
                if (position == activeTab) return
                val proceed: () -> Unit = {
                    activeTab = position
                    renderActiveTab()
                }
                if (isActiveTabDirty()) {
                    confirmDiscard(proceed)
                } else {
                    proceed()
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    /**
     * 给每个 TextInputLayout 设置 "默认 N 字" helper text，N 取自 PromptDefaults 常量长度。
     * 让用户能看到默认 prompt 的体量。
     */
    private fun setupHelperTexts() {
        binding.scriptCreateInputLayout.helperText = defaultLengthText(PromptDefaults.SCRIPT_CREATE_PROMPT)
        binding.scriptRewriteInputLayout.helperText = defaultLengthText(PromptDefaults.SCRIPT_REWRITE_PROMPT)
        binding.characterExtractInputLayout.helperText = defaultLengthText(PromptDefaults.CHARACTER_EXTRACT_PROMPT)
        binding.storyboardInputLayout.helperText = defaultLengthText(PromptDefaults.STORYBOARD_PROMPT)
    }

    private fun defaultLengthText(default: String): String {
        return getString(R.string.manage_prompts_field_default_length, default.length)
    }

    private fun setupClickListeners() {
        binding.closeButton.setOnClickListener { finish() }
        // 脚本 tab：2 个字段共用 1 组按钮
        binding.resetScriptButton.setOnClickListener { onResetScriptClick() }
        binding.saveScriptButton.setOnClickListener { onSaveScriptClick() }
        // 角色提取 tab
        binding.resetCharacterButton.setOnClickListener { onResetCharacterClick() }
        binding.saveCharacterButton.setOnClickListener { onSaveCharacterClick() }
        // 分镜 tab
        binding.resetStoryboardButton.setOnClickListener { onResetStoryboardClick() }
        binding.saveStoryboardButton.setOnClickListener { onSaveStoryboardClick() }
    }

    // ────────────── 渲染 ──────────────

    /**
     * 渲染当前 tab 的内容：仅显示对应 panel，回填 customXxx ?? default。
     */
    private fun renderActiveTab() {
        binding.scriptPanel.visibility = if (activeTab == TAB_SCRIPT) View.VISIBLE else View.GONE
        binding.characterPanel.visibility = if (activeTab == TAB_CHARACTER) View.VISIBLE else View.GONE
        binding.storyboardPanel.visibility = if (activeTab == TAB_STORYBOARD) View.VISIBLE else View.GONE

        when (activeTab) {
            TAB_SCRIPT -> {
                binding.scriptCreateInput.setText(
                    currentSettings.customScriptCreatePrompt?.takeIf { it.isNotBlank() }
                        ?: PromptDefaults.SCRIPT_CREATE_PROMPT
                )
                binding.scriptCreateInput.setSelection(0)
                binding.scriptRewriteInput.setText(
                    currentSettings.customScriptRewritePrompt?.takeIf { it.isNotBlank() }
                        ?: PromptDefaults.SCRIPT_REWRITE_PROMPT
                )
                binding.scriptRewriteInput.setSelection(0)
            }
            TAB_CHARACTER -> {
                binding.characterExtractInput.setText(
                    currentSettings.customCharacterExtractPrompt?.takeIf { it.isNotBlank() }
                        ?: PromptDefaults.CHARACTER_EXTRACT_PROMPT
                )
                binding.characterExtractInput.setSelection(0)
            }
            TAB_STORYBOARD -> {
                binding.storyboardInput.setText(
                    currentSettings.customStoryboardPrompt?.takeIf { it.isNotBlank() }
                        ?: PromptDefaults.STORYBOARD_PROMPT
                )
                binding.storyboardInput.setSelection(0)
            }
        }
        binding.statusText.text = ""
    }

    /**
     * 当前 tab 是否有未保存修改：与 store 的 customXxx ?? default 对比。
     */
    private fun isActiveTabDirty(): Boolean {
        return when (activeTab) {
            TAB_SCRIPT -> {
                val curCreate = binding.scriptCreateInput.text?.toString().orEmpty()
                val curRewrite = binding.scriptRewriteInput.text?.toString().orEmpty()
                curCreate != (currentSettings.customScriptCreatePrompt?.takeIf { it.isNotBlank() }
                    ?: PromptDefaults.SCRIPT_CREATE_PROMPT) ||
                    curRewrite != (currentSettings.customScriptRewritePrompt?.takeIf { it.isNotBlank() }
                        ?: PromptDefaults.SCRIPT_REWRITE_PROMPT)
            }
            TAB_CHARACTER -> {
                val cur = binding.characterExtractInput.text?.toString().orEmpty()
                cur != (currentSettings.customCharacterExtractPrompt?.takeIf { it.isNotBlank() }
                    ?: PromptDefaults.CHARACTER_EXTRACT_PROMPT)
            }
            TAB_STORYBOARD -> {
                val cur = binding.storyboardInput.text?.toString().orEmpty()
                cur != (currentSettings.customStoryboardPrompt?.takeIf { it.isNotBlank() }
                    ?: PromptDefaults.STORYBOARD_PROMPT)
            }
            else -> false
        }
    }

    // ────────────── 按钮处理 ──────────────

    /**
     * "脚本" tab：把 2 个字段一起保存（trim → 空串视为使用默认）。
     */
    private fun onSaveScriptClick() {
        val createValue = binding.scriptCreateInput.text?.toString()?.trim().orEmpty()
        val rewriteValue = binding.scriptRewriteInput.text?.toString()?.trim().orEmpty()
        val newSettings = currentSettings.copy(
            customScriptCreatePrompt = createValue.takeIf { it.isNotEmpty() },
            customScriptRewritePrompt = rewriteValue.takeIf { it.isNotEmpty() }
        )
        persistSave(newSettings, R.string.manage_prompts_save_done, R.string.manage_prompts_save_failed)
    }

    /**
     * "脚本" tab：清空 2 个字段回到默认。
     */
    private fun onResetScriptClick() {
        val newSettings = currentSettings.copy(
            customScriptCreatePrompt = null,
            customScriptRewritePrompt = null
        )
        persistSave(newSettings, R.string.manage_prompts_reset_done, R.string.manage_prompts_save_failed)
    }

    private fun onSaveCharacterClick() {
        val value = binding.characterExtractInput.text?.toString()?.trim().orEmpty()
        val newSettings = currentSettings.copy(
            customCharacterExtractPrompt = value.takeIf { it.isNotEmpty() }
        )
        persistSave(newSettings, R.string.manage_prompts_save_done, R.string.manage_prompts_save_failed)
    }

    private fun onResetCharacterClick() {
        val newSettings = currentSettings.copy(customCharacterExtractPrompt = null)
        persistSave(newSettings, R.string.manage_prompts_reset_done, R.string.manage_prompts_save_failed)
    }

    private fun onSaveStoryboardClick() {
        val value = binding.storyboardInput.text?.toString()?.trim().orEmpty()
        val newSettings = currentSettings.copy(
            customStoryboardPrompt = value.takeIf { it.isNotEmpty() }
        )
        persistSave(newSettings, R.string.manage_prompts_save_done, R.string.manage_prompts_save_failed)
    }

    private fun onResetStoryboardClick() {
        val newSettings = currentSettings.copy(customStoryboardPrompt = null)
        persistSave(newSettings, R.string.manage_prompts_reset_done, R.string.manage_prompts_save_failed)
    }

    /**
     * 通用保存：写 store → 更新内存 → Toast + 状态栏提示。
     */
    private fun persistSave(
        newSettings: AgnesSettings,
        successMsgRes: Int,
        failureMsgRes: Int
    ) {
        runCatching { settingsStore.save(newSettings) }
            .onSuccess {
                currentSettings = newSettings
                renderActiveTab()
                binding.statusText.text = getString(successMsgRes)
                Toast.makeText(this, successMsgRes, Toast.LENGTH_SHORT).show()
            }
            .onFailure {
                Toast.makeText(this, failureMsgRes, Toast.LENGTH_SHORT).show()
            }
    }

    // ────────────── 脏检查二次确认 ──────────────

    private fun confirmDiscard(onProceed: () -> Unit) {
        AlertDialog.Builder(this)
            .setTitle(R.string.manage_prompts_discard_title)
            .setMessage(R.string.manage_prompts_discard_message)
            .setPositiveButton(R.string.manage_prompts_discard_confirm) { _, _ -> onProceed() }
            .setNegativeButton(R.string.manage_prompts_discard_cancel) { _, _ ->
                binding.promptSpinner.setSelection(activeTab)
            }
            .show()
    }

    // ────────────── Tab 索引常量 ──────────────

    companion object {
        private const val TAB_SCRIPT = 0
        private const val TAB_CHARACTER = 1
        private const val TAB_STORYBOARD = 2
    }
}
