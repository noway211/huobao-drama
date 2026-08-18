package com.huobao.zdrama.ui.project

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.huobao.zdrama.R
import com.huobao.zdrama.databinding.ItemCharacterBinding
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character
import java.io.File

class CharacterAdapter(
    private val onEditAppearance: (Character) -> Unit,
    private val onRegenerateImage: (Character) -> Unit,
    private val onPreviewImage: (Character) -> Unit,
    private val onDeleteImage: (Character) -> Unit
) : RecyclerView.Adapter<CharacterAdapter.CharacterViewHolder>() {
    private val items = mutableListOf<Character>()

    fun submitList(characters: List<Character>) {
        items.clear()
        items.addAll(characters)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): CharacterViewHolder {
        val binding = ItemCharacterBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return CharacterViewHolder(binding)
    }

    override fun onBindViewHolder(holder: CharacterViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    inner class CharacterViewHolder(
        private val binding: ItemCharacterBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(character: Character) {
            val context = binding.root.context
            binding.nameText.text = character.name
            binding.roleText.text = character.role.ifBlank { context.getString(R.string.project_character_role_unknown) }
            binding.descriptionText.text = character.description.ifBlank { context.getString(R.string.project_character_description_empty) }
            binding.appearanceText.text = character.appearance.ifBlank { context.getString(R.string.project_character_appearance_empty) }
            binding.statusText.text = context.getString(R.string.project_character_image_status_label) + "：" + statusDisplay(context, character)

            val localFile = character.imageLocalPath
                ?.takeIf { it.isNotBlank() }
                ?.let { File(it) }
                ?.takeIf { it.exists() }
            when {
                localFile != null -> {
                    val bitmap = decodeSampled(localFile.absolutePath, AVATAR_TARGET_PX)
                    if (bitmap != null) {
                        binding.avatarImage.setImageBitmap(bitmap)
                    } else {
                        binding.avatarImage.setImageDrawable(null)
                    }
                }
                else -> binding.avatarImage.setImageDrawable(null)
            }

            binding.avatarImage.setOnClickListener { onPreviewImage(character) }
            binding.editAppearanceButton.setOnClickListener { onEditAppearance(character) }
            binding.regenerateImageButton.setOnClickListener { onRegenerateImage(character) }
            // 仅当已生成图（本地或远端）才显示删除按钮，与鸿蒙端 `imageStatus === COMPLETED` 守卫一致
            val hasImage = !character.imageLocalPath.isNullOrBlank() || !character.imageUrl.isNullOrBlank()
            binding.deleteImageButton.visibility = if (hasImage) View.VISIBLE else View.GONE
            binding.deleteImageButton.setOnClickListener { onDeleteImage(character) }
        }

        private fun statusDisplay(context: android.content.Context, character: Character): String {
            val label = context.getString(
                when (character.imageStatus) {
                    AssetStatus.PENDING -> R.string.asset_pending
                    AssetStatus.PROCESSING -> R.string.asset_processing
                    AssetStatus.COMPLETED -> R.string.asset_completed
                    AssetStatus.FAILED -> R.string.asset_failed
                }
            )
            if (character.imageStatus == AssetStatus.FAILED && !character.imageErrorMessage.isNullOrBlank()) {
                return "$label（${character.imageErrorMessage}）"
            }
            return label
        }

        private fun decodeSampled(path: String, targetPx: Int): Bitmap? {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            val maxSide = maxOf(bounds.outWidth, bounds.outHeight)
            while (maxSide / sample > targetPx) sample *= 2
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            return runCatching { BitmapFactory.decodeFile(path, opts) }.getOrNull()
        }
    }

    companion object {
        private const val AVATAR_TARGET_PX = 256
    }
}
