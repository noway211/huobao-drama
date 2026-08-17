package com.huobao.zdrama.ui.settings

import android.graphics.Typeface
import android.os.Bundle
import android.view.View
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
 * - 顶部 3 个 tab 同时可见（脚本 / 角色提取 / 分镜），active tab 用 primary 蓝 + bold + 2dp 下划线
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
        setupTabs()
        setupHelperTexts()
        setupClickListeners()
    }

    override fun onResume() {
        super.onResume()
        currentSettings = settingsStore.load()
        renderActiveTab()
    }

    // ────────────── 初始化 ──────────────

    /**
     * 3 个 tab 同时显示，点击切换；切换前做脏检查。
     * 与 Harmony 端 `Tabs({ index: $$this.activePromptTab })` 行为一致。
     */
    private fun setupTabs() {
        binding.tabScriptContainer.setOnClickListener { onTabClick(TAB_SCRIPT) }
        binding.tabCharacterContainer.setOnClickListener { onTabClick(TAB_CHARACTER) }
        binding.tabStoryboardContainer.setOnClickListener { onTabClick(TAB_STORYBOARD) }
    }

    private fun onTabClick(targetIndex: Int) {
        if (targetIndex == activeTab) return
        val proceed: () -> Unit = {
            activeTab = targetIndex
            renderActiveTab()
        }
        if (isActiveTabDirty()) {
            confirmDiscard(proceed)
        } else {
            proceed()
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

    // ────────────── Tab 视觉状态 ──────────────

    /**
     * 切换 3 个 tab 的 active/inactive 视觉：
     * - active: 蓝色 + bold + 2dp 蓝色下划线
     * - inactive: 灰色 + normal + 透明下划线（占位避免高度跳变）
     */
    private fun applyTabStyles() {
        applyTabStyle(binding.tabScriptLabel, binding.tabScriptIndicator, activeTab == TAB_SCRIPT)
        applyTabStyle(binding.tabCharacterLabel, binding.tabCharacterIndicator, activeTab == TAB_CHARACTER)
        applyTabStyle(binding.tabStoryboardLabel, binding.tabStoryboardIndicator, activeTab == TAB_STORYBOARD)
    }

    private fun applyTabStyle(label: android.widget.TextView, indicator: View, isActive: Boolean) {
        if (isActive) {
            label.setTextColor(getColor(R.color.zdrama_primary))
            label.setTypeface(label.typeface, Typeface.BOLD)
            indicator.setBackgroundColor(getColor(R.color.zdrama_primary))
        } else {
            label.setTextColor(getColor(R.color.zdrama_text_secondary))
            label.setTypeface(label.typeface, Typeface.NORMAL)
            indicator.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        }
    }

    // ────────────── 渲染 ──────────────

    /**
     * 渲染当前 tab 的内容：仅显示对应 panel，回填 customXxx ?? default。
     */
    private fun renderActiveTab() {
        applyTabStyles()
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
            .setNegativeButton(R.string.manage_prompts_discard_cancel) { _, _ -> applyTabStyles() }
            .show()
    }

    // ────────────── Tab 索引常量 ──────────────

    companion object {
        private const val TAB_SCRIPT = 0
        private const val TAB_CHARACTER = 1
        private const val TAB_STORYBOARD = 2
    }
}
