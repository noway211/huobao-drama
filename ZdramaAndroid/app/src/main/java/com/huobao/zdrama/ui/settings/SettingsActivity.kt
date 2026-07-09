package com.huobao.zdrama.ui.settings

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.databinding.ActivitySettingsBinding
import com.huobao.zdrama.domain.usecase.TestAgnesConnectionUseCase
import kotlinx.coroutines.launch

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding
    private lateinit var settingsStore: AgnesSettingsStore
    private val testConnectionUseCase = TestAgnesConnectionUseCase()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        settingsStore = AgnesSettingsStore(this)
        render(settingsStore.load())

        binding.saveButton.setOnClickListener {
            runCatching { settingsStore.save(readForm()) }
                .onSuccess {
                    Toast.makeText(this, R.string.settings_saved, Toast.LENGTH_SHORT).show()
                }
                .onFailure {
                    Toast.makeText(this, R.string.settings_save_failed, Toast.LENGTH_SHORT).show()
                }
        }
        binding.testTextModelButton.setOnClickListener {
            testTextModel()
        }
    }

    private fun render(settings: AgnesSettings) {
        binding.apiKeyInput.setText(settings.apiKey)
        binding.baseUrlInput.setText(settings.baseUrl)
        binding.textModelInput.setText(settings.textModel)
        binding.imageModelInput.setText(settings.imageModel)
        binding.videoModelInput.setText(settings.videoModel)
    }

    private fun readForm(): AgnesSettings {
        return AgnesSettings(
            apiKey = binding.apiKeyInput.text?.toString().orEmpty(),
            baseUrl = binding.baseUrlInput.text?.toString().orEmpty(),
            textModel = binding.textModelInput.text?.toString().orEmpty(),
            imageModel = binding.imageModelInput.text?.toString().orEmpty(),
            videoModel = binding.videoModelInput.text?.toString().orEmpty(),
            requestTimeoutSeconds = AgnesSettings.DEFAULT_TIMEOUT_SECONDS
        )
    }

    private fun testTextModel() {
        val settings = readForm()
        binding.testTextModelButton.isEnabled = false
        lifecycleScope.launch {
            val result = runCatching {
                settingsStore.save(settings)
                testConnectionUseCase.execute(settings)
            }.getOrElse { Result.failure(it) }
            binding.testTextModelButton.isEnabled = true
            val messageRes = if (result.isSuccess) {
                R.string.settings_test_success
            } else {
                R.string.settings_test_failed
            }
            Toast.makeText(this@SettingsActivity, messageRes, Toast.LENGTH_SHORT).show()
        }
    }
}
