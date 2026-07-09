package com.huobao.zdrama.ui.create

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityCreateProjectBinding
import com.huobao.zdrama.domain.model.CreateDramaInput
import com.huobao.zdrama.domain.usecase.CreateDramaUseCase
import com.huobao.zdrama.ui.project.ProjectDetailActivity
import kotlinx.coroutines.launch

class CreateProjectActivity : AppCompatActivity() {
    private lateinit var binding: ActivityCreateProjectBinding
    private lateinit var createDramaUseCase: CreateDramaUseCase

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityCreateProjectBinding.inflate(layoutInflater)
        setContentView(binding.root)

        createDramaUseCase = CreateDramaUseCase(DramaRepository(this))

        binding.saveButton.setOnClickListener {
            saveProject()
        }
    }

    private fun saveProject() {
        val title = binding.titleInput.text?.toString()?.trim().orEmpty()
        val prompt = binding.promptInput.text?.toString()?.trim().orEmpty()
        if (title.isBlank() || prompt.isBlank()) {
            Toast.makeText(this, R.string.project_required_error, Toast.LENGTH_SHORT).show()
            return
        }

        val shotCount = binding.shotCountInput.text?.toString()?.toIntOrNull() ?: 0
        val duration = binding.durationInput.text?.toString()?.toIntOrNull() ?: 0
        if (shotCount <= 0 || duration <= 0) {
            Toast.makeText(this, R.string.project_invalid_number_error, Toast.LENGTH_SHORT).show()
            return
        }

        val input = CreateDramaInput(
            title = title,
            prompt = prompt,
            style = binding.styleInput.text?.toString()?.trim().orEmpty().ifBlank { getString(R.string.project_default_style) },
            targetAudience = binding.audienceInput.text?.toString()?.trim().orEmpty().ifBlank { getString(R.string.project_default_audience) },
            aspectRatio = binding.aspectRatioInput.text?.toString()?.trim().orEmpty().ifBlank { "9:16" },
            shotCount = shotCount,
            shotDurationSeconds = duration
        )

        binding.saveButton.isEnabled = false
        lifecycleScope.launch {
            runCatching { createDramaUseCase.execute(input) }
                .onSuccess { projectId ->
                    Toast.makeText(this@CreateProjectActivity, R.string.project_saved, Toast.LENGTH_SHORT).show()
                    startActivity(
                        Intent(this@CreateProjectActivity, ProjectDetailActivity::class.java)
                            .putExtra(ProjectDetailActivity.EXTRA_PROJECT_ID, projectId)
                    )
                    finish()
                }
                .onFailure {
                    binding.saveButton.isEnabled = true
                    Toast.makeText(this@CreateProjectActivity, R.string.project_save_failed, Toast.LENGTH_SHORT).show()
                }
        }
    }
}
