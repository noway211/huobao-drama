package com.huobao.zdrama.ui.project

import android.graphics.BitmapFactory
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.huobao.zdrama.R
import com.huobao.zdrama.databinding.ItemImageGalleryBinding
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import java.io.File

class ImageGalleryAdapter(
    private val onLongClick: (StoryboardShot) -> Unit = {}
) : RecyclerView.Adapter<ImageGalleryAdapter.ImageViewHolder>() {
    private val shots = mutableListOf<StoryboardShot>()

    fun submitList(items: List<StoryboardShot>) {
        shots.clear()
        shots.addAll(items)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ImageViewHolder {
        val binding = ItemImageGalleryBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ImageViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ImageViewHolder, position: Int) {
        holder.bind(shots[position])
    }

    override fun getItemCount(): Int = shots.size

    inner class ImageViewHolder(
        private val binding: ItemImageGalleryBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(shot: StoryboardShot) {
            val context = binding.root.context
            binding.shotTitleText.text = "#${shot.shotNumber}  ${shot.scene}"

            val localFile = shot.imageLocalPath
                ?.takeIf { it.isNotBlank() }
                ?.let { File(it) }
                ?.takeIf { it.exists() }
            when {
                localFile != null -> {
                    val bitmap = decodeSampled(localFile.absolutePath, IMAGE_TARGET_PX)
                    if (bitmap != null) {
                        binding.shotImage.setImageBitmap(bitmap)
                    } else {
                        binding.shotImage.setImageDrawable(null)
                    }
                    binding.shotStatusText.text = context.getString(
                        R.string.project_image_status_label
                    ) + "：" + statusDisplay(context, shot.imageStatus)
                }
                !shot.imageUrl.isNullOrBlank() -> {
                    binding.shotImage.setImageDrawable(null)
                    binding.shotStatusText.text = context.getString(R.string.project_image_placeholder_remote) +
                        "\n" + shot.imageUrl
                }
                else -> {
                    binding.shotImage.setImageDrawable(null)
                    val statusText = statusDisplay(context, shot.imageStatus)
                    val fallback = context.getString(R.string.project_image_placeholder_pending)
                    binding.shotStatusText.text = "$fallback（$statusText）"
                }
            }
            // 仅当该 shot 有 image（本地或远端）时才允许长按删除
            val canDelete = !shot.imageLocalPath.isNullOrBlank() || !shot.imageUrl.isNullOrBlank()
            binding.root.setOnLongClickListener {
                if (canDelete) onLongClick(shot)
                canDelete
            }
        }

        private fun statusDisplay(context: android.content.Context, status: AssetStatus): String {
            return context.getString(
                when (status) {
                    AssetStatus.PENDING -> R.string.asset_pending
                    AssetStatus.PROCESSING -> R.string.asset_processing
                    AssetStatus.COMPLETED -> R.string.asset_completed
                    AssetStatus.FAILED -> R.string.asset_failed
                }
            )
        }

        private fun decodeSampled(path: String, targetPx: Int): android.graphics.Bitmap? {
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
        private const val IMAGE_TARGET_PX = 1024
    }
}
