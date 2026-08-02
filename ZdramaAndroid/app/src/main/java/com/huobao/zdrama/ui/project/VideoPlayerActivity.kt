package com.huobao.zdrama.ui.project

import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.MediaController
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityVideoPlayerBinding
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import java.io.File
import kotlinx.coroutines.launch

class VideoPlayerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityVideoPlayerBinding
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private val playableShots = mutableListOf<StoryboardShot>()
    private var currentIndex = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityVideoPlayerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        getStoryboardsUseCase = GetStoryboardsUseCase(DramaRepository(this))
        binding.videoView.setMediaController(MediaController(this).apply {
            setAnchorView(binding.videoView)
        })
        binding.videoView.setOnCompletionListener { playNextIfAvailable() }
        binding.videoView.setOnErrorListener { _: MediaPlayer?, what: Int, extra: Int ->
            Log.e(TAG, "Video playback failed: what=$what, extra=$extra")
            Toast.makeText(this, R.string.video_playback_failed, Toast.LENGTH_SHORT).show()
            true
        }
        binding.previousButton.setOnClickListener { playAt(currentIndex - 1) }
        binding.playButton.setOnClickListener {
            if (binding.videoView.isPlaying) {
                binding.videoView.pause()
                binding.playButton.setText(R.string.video_play)
            } else {
                binding.videoView.start()
                binding.playButton.setText(R.string.video_pause)
            }
        }
        binding.nextButton.setOnClickListener { playAt(currentIndex + 1) }

        val videoPath = intent.getStringExtra(EXTRA_VIDEO_PATH)
        if (!videoPath.isNullOrBlank()) {
            playSingleVideo(videoPath)
            return
        }

        val projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        if (projectId <= 0L) {
            showNoVideos()
            return
        }
        loadVideos(projectId)
    }

    override fun onStop() {
        binding.videoView.stopPlayback()
        super.onStop()
    }

    private fun loadVideos(projectId: Long) {
        lifecycleScope.launch {
            val shots = getStoryboardsUseCase.execute(projectId)
                .filter { it.playableVideoUri() != null }
            playableShots.clear()
            playableShots.addAll(shots)
            if (playableShots.isEmpty()) {
                showNoVideos()
            } else {
                playAt(0)
            }
        }
    }

    private fun playSingleVideo(videoPath: String) {
        val file = File(videoPath)
        if (!file.exists()) {
            showNoVideos()
            return
        }
        binding.shotText.setText(R.string.video_player_final_label)
        binding.previousButton.isEnabled = false
        binding.nextButton.isEnabled = false
        val uri = Uri.fromFile(file)
        Log.d(TAG, "Playing final video: path=${file.absolutePath}, exists=${file.exists()}, size=${file.length()}")
        binding.videoView.setOnPreparedListener {
            binding.videoView.start()
            binding.playButton.setText(R.string.video_pause)
        }
        binding.videoView.setVideoURI(uri)
    }

    private fun playAt(index: Int) {
        if (index !in playableShots.indices) return
        currentIndex = index
        val shot = playableShots[index]
        binding.shotText.text = getString(
            R.string.video_player_shot_label,
            shot.shotNumber,
            index + 1,
            playableShots.size
        )
        val uri = shot.playableVideoUri() ?: return
        Log.d(TAG, "Playing storyboard video: shotId=${shot.id}, uri=$uri, localPath=${shot.videoLocalPath}, url=${shot.videoUrl}")
        binding.videoView.setOnPreparedListener {
            binding.videoView.start()
            binding.playButton.setText(R.string.video_pause)
        }
        binding.videoView.setVideoURI(uri)
        updateNavigationButtons()
    }

    private fun playNextIfAvailable() {
        if (currentIndex < playableShots.lastIndex) {
            playAt(currentIndex + 1)
        } else {
            binding.playButton.setText(R.string.video_play)
        }
    }

    private fun updateNavigationButtons() {
        binding.previousButton.isEnabled = currentIndex > 0
        binding.nextButton.isEnabled = currentIndex < playableShots.lastIndex
    }

    private fun StoryboardShot.playableVideoUri(): Uri? {
        val localFile = videoLocalPath
            ?.takeIf { it.isNotBlank() }
            ?.let { File(it) }
            ?.takeIf { it.exists() }
        if (localFile != null) return Uri.fromFile(localFile)
        return videoUrl
            ?.takeIf { it.isNotBlank() }
            ?.let { Uri.parse(it) }
    }

    private fun showNoVideos() {
        Toast.makeText(this, R.string.video_no_generated_videos, Toast.LENGTH_SHORT).show()
        finish()
    }

    companion object {
        private const val TAG = "VideoPlayerActivity"
        const val EXTRA_PROJECT_ID = "extra_project_id"
        const val EXTRA_VIDEO_PATH = "extra_video_path"
    }
}
