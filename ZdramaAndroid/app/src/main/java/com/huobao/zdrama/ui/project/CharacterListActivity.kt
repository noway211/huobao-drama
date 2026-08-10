package com.huobao.zdrama.ui.project

import android.app.AlertDialog
import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.AgnesTextRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.databinding.ActivityCharacterListBinding
import com.huobao.zdrama.domain.model.Character
import com.huobao.zdrama.domain.usecase.GenerateCharacterImagesUseCase
import com.huobao.zdrama.domain.usecase.GenerateSingleCharacterImageUseCase
import com.huobao.zdrama.domain.usecase.GetCharactersUseCase
import com.huobao.zdrama.domain.usecase.GetProjectDetailUseCase
import com.huobao.zdrama.domain.usecase.UpdateCharacterAppearanceUseCase
import com.huobao.zdrama.worker.GenerationWorker
import java.io.File
import kotlinx.coroutines.launch

class CharacterListActivity : AppCompatActivity() {
    private lateinit var binding: ActivityCharacterListBinding
    private lateinit var dramaRepository: DramaRepository
    private lateinit var getProjectDetailUseCase: GetProjectDetailUseCase
    private lateinit var getCharactersUseCase: GetCharactersUseCase
    private lateinit var updateAppearanceUseCase: UpdateCharacterAppearanceUseCase
    private lateinit var singleImageUseCase: GenerateSingleCharacterImageUseCase
    private lateinit var allImagesUseCase: GenerateCharacterImagesUseCase
    private val adapter = CharacterAdapter(
        onEditAppearance = { ch -> showEditAppearanceDialog(ch) },
        onRegenerateImage = { ch -> regenerateSingle(ch) },
        onPreviewImage = { ch -> previewImage(ch) }
    )
    private var projectId: Long = 0L
    private var cachedCharacters: List<Character> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityCharacterListBinding.inflate(layoutInflater)
        setContentView(binding.root)

        dramaRepository = DramaRepository(this)
        getProjectDetailUseCase = GetProjectDetailUseCase(dramaRepository)
        getCharactersUseCase = GetCharactersUseCase(dramaRepository)
        updateAppearanceUseCase = UpdateCharacterAppearanceUseCase(dramaRepository)
        val mediaDownloadRepository = MediaDownloadRepository(this)
        singleImageUseCase = GenerateSingleCharacterImageUseCase(
            dramaRepository,
            AgnesImageRepository(),
            mediaDownloadRepository
        )
        allImagesUseCase = GenerateCharacterImagesUseCase(
            dramaRepository,
            AgnesImageRepository(),
            mediaDownloadRepository
        )

        binding.characterList.layoutManager = LinearLayoutManager(this)
        binding.characterList.adapter = adapter

        binding.generateAllButton.setOnClickListener { confirmGenerateAll() }

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        if (projectId <= 0L) {
            finishWithMessage(R.string.project_missing)
            return
        }
        loadCharacters()
    }

    override fun onResume() {
        super.onResume()
        if (projectId > 0L) loadCharacters()
    }

    private fun loadCharacters() {
        lifecycleScope.launch {
            val project = getProjectDetailUseCase.execute(projectId)
            if (project == null) {
                finishWithMessage(R.string.project_missing)
                return@launch
            }
            val characters = getCharactersUseCase.execute(projectId)
            cachedCharacters = characters
            binding.titleText.text = project.title
            binding.countText.text = getString(R.string.project_character_count_label, characters.size)
            adapter.submitList(characters)
            if (characters.isEmpty()) {
                binding.emptyText.visibility = View.VISIBLE
                binding.characterList.visibility = View.GONE
                binding.generateAllButton.isEnabled = false
            } else {
                binding.emptyText.visibility = View.GONE
                binding.characterList.visibility = View.VISIBLE
                binding.generateAllButton.isEnabled = true
            }
        }
    }

    private fun showEditAppearanceDialog(character: Character) {
        val input = EditText(this).apply {
            setText(character.appearance)
            minLines = 4
            setSingleLine(false)
            isVerticalScrollBarEnabled = true
        }
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.project_character_edit_appearance_title, character.name))
            .setView(input)
            .setPositiveButton(R.string.project_save) { _, _ ->
                val newText = input.text?.toString()?.trim().orEmpty()
                if (newText.isBlank()) {
                    Toast.makeText(this, R.string.project_character_appearance_empty_toast, Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                if (newText == character.appearance) {
                    return@setPositiveButton
                }
                saveAppearance(character, newText)
            }
            .setNegativeButton(R.string.project_delete_cancel, null)
            .show()
    }

    private fun saveAppearance(character: Character, appearance: String) {
        lifecycleScope.launch {
            val ok = updateAppearanceUseCase.updateAppearance(character.id, appearance)
            if (ok) {
                Toast.makeText(this@CharacterListActivity, R.string.project_character_appearance_saved, Toast.LENGTH_SHORT).show()
                loadCharacters()
            } else {
                Toast.makeText(this@CharacterListActivity, R.string.project_character_appearance_save_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun regenerateSingle(character: Character) {
        if (AgnesSettingsStore(this).load().apiKey.isBlank()) {
            Toast.makeText(this, R.string.project_generation_missing_api_key, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val result = singleImageUseCase.execute(projectId, character.id, AgnesSettingsStore(this@CharacterListActivity).load())
            if (result.isSuccess) {
                Toast.makeText(this@CharacterListActivity, R.string.project_character_image_regenerated, Toast.LENGTH_SHORT).show()
                loadCharacters()
            } else {
                val error = result.exceptionOrNull()?.message ?: getString(R.string.project_character_image_regenerate_failed)
                Toast.makeText(this@CharacterListActivity, error, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun previewImage(character: Character) {
        val path = character.imageLocalPath
        if (path.isNullOrBlank() || !File(path).exists()) {
            Toast.makeText(this, R.string.project_character_no_local_image, Toast.LENGTH_SHORT).show()
            return
        }
        val fragment = CharacterImagePreviewDialogFragment.newInstance(path)
        fragment.show(supportFragmentManager, CharacterImagePreviewDialogFragment.TAG)
    }

    private fun confirmGenerateAll() {
        if (cachedCharacters.isEmpty()) {
            Toast.makeText(this, R.string.project_no_characters, Toast.LENGTH_SHORT).show()
            return
        }
        if (AgnesSettingsStore(this).load().apiKey.isBlank()) {
            Toast.makeText(this, R.string.project_generation_missing_api_key, Toast.LENGTH_SHORT).show()
            return
        }
        val anyCompleted = cachedCharacters.any { it.imageLocalPath.isNullOrBlank().not() }
        val messageRes = if (anyCompleted) R.string.project_regenerate_character_images_message else 0
        if (messageRes != 0) {
            AlertDialog.Builder(this)
                .setTitle(R.string.project_regenerate_title)
                .setMessage(messageRes)
                .setNegativeButton(R.string.project_regenerate_cancel, null)
                .setPositiveButton(R.string.project_regenerate_confirm) { _, _ -> enqueueGenerateAll() }
                .show()
        } else {
            enqueueGenerateAll()
        }
    }

    private fun enqueueGenerateAll() {
        GenerationWorker.enqueue(this, projectId, GenerationWorker.STAGE_CHARACTER_IMAGE)
        Toast.makeText(this, R.string.project_character_image_queued, Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun finishWithMessage(messageRes: Int) {
        Toast.makeText(this, messageRes, Toast.LENGTH_SHORT).show()
        finish()
    }

    companion object {
        const val EXTRA_PROJECT_ID = "extra_project_id"
    }
}
