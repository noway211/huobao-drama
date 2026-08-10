package com.huobao.zdrama.ui.project

import android.app.Dialog
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import androidx.fragment.app.DialogFragment
import com.huobao.zdrama.databinding.FragmentCharacterImagePreviewBinding
import java.io.File

class CharacterImagePreviewDialogFragment : DialogFragment() {
    private var _binding: FragmentCharacterImagePreviewBinding? = null
    private val binding get() = _binding!!

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setStyle(STYLE_NORMAL, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        return dialog
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentCharacterImagePreviewBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val path = arguments?.getString(ARG_PATH)
        if (path.isNullOrBlank() || !File(path).exists()) {
            binding.previewImage.setImageDrawable(null)
        } else {
            val bitmap = decodeSampled(path, PREVIEW_TARGET_PX)
            if (bitmap != null) {
                binding.previewImage.setImageBitmap(bitmap)
            } else {
                binding.previewImage.setImageDrawable(null)
            }
        }
        binding.closeButton.setOnClickListener { dismiss() }
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.let { window ->
            window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
            window.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
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

    companion object {
        private const val ARG_PATH = "arg_path"
        private const val PREVIEW_TARGET_PX = 2048
        const val TAG = "CharacterImagePreview"

        fun newInstance(path: String): CharacterImagePreviewDialogFragment {
            val fragment = CharacterImagePreviewDialogFragment()
            fragment.arguments = Bundle().apply { putString(ARG_PATH, path) }
            return fragment
        }
    }
}
