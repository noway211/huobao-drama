package com.huobao.zdrama.ui.project

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.MediaController
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.repository.AlbumSaver
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.databinding.ActivityVideoPlayerBinding
import com.huobao.zdrama.domain.model.StoryboardShot
import com.huobao.zdrama.domain.usecase.GetStoryboardsUseCase
import java.io.File
import kotlinx.coroutines.launch

class VideoPlayerActivity : AppCompatActivity() {
    private lateinit var binding: ActivityVideoPlayerBinding
    private lateinit var getStoryboardsUseCase: GetStoryboardsUseCase
    private lateinit var repository: DramaRepository
    private val playableShots = mutableListOf<StoryboardShot>()
    private var currentIndex = 0
    private var projectId: Long = 0L
    private var episodeId: Long = 0L
    private var isFinalVideoMode = false
    private var finalVideoPath: String? = null
    private var finalVideoTitle: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityVideoPlayerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        repository = DramaRepository(this)
        getStoryboardsUseCase = GetStoryboardsUseCase(repository)
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
        binding.deleteCurrentButton.setOnClickListener { confirmDeleteCurrent() }
        binding.deleteAllButton.setOnClickListener { confirmDeleteAll() }
        binding.deleteFinalButton.setOnClickListener { confirmDeleteFinal() }
        binding.saveFinalButton.setOnClickListener { saveCurrentToAlbum() }

        projectId = intent.getLongExtra(EXTRA_PROJECT_ID, 0L)
        episodeId = intent.getLongExtra(EXTRA_EPISODE_ID, 0L)

        val videoPath = intent.getStringExtra(EXTRA_VIDEO_PATH)
        if (!videoPath.isNullOrBlank()) {
            playSingleVideo(videoPath)
            return
        }

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
            val shots = if (episodeId > 0L) {
                getStoryboardsUseCase.execute(projectId, episodeId)
            } else {
                getStoryboardsUseCase.execute(projectId)
            }.filter { it.playableVideoUri() != null }
            playableShots.clear()
            playableShots.addAll(shots)
            if (playableShots.isEmpty()) {
                showNoVideos()
            } else {
                // 启用分镜模式按钮组（分镜也支持保存到相册）
                binding.deleteAllButton.visibility = View.VISIBLE
                binding.deleteCurrentButton.visibility = View.VISIBLE
                binding.saveFinalButton.visibility = View.VISIBLE
                binding.deleteFinalButton.visibility = View.GONE
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
        isFinalVideoMode = true
        finalVideoPath = videoPath
        finalVideoTitle = intent.getStringExtra(EXTRA_PROJECT_TITLE)
        binding.shotText.setText(R.string.video_player_final_label)
        binding.previousButton.isEnabled = false
        binding.nextButton.isEnabled = false
        // 启用成片模式按钮组
        binding.deleteAllButton.visibility = View.GONE
        binding.deleteCurrentButton.visibility = View.GONE
        binding.saveFinalButton.visibility = View.VISIBLE
        binding.deleteFinalButton.visibility = View.VISIBLE
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

    // ────────────── 删除操作 ──────────────

    private fun confirmDeleteCurrent() {
        if (playableShots.isEmpty() || currentIndex !in playableShots.indices) return
        val shot = playableShots[currentIndex]
        AlertDialog.Builder(this)
            .setTitle(R.string.project_video_delete_title)
            .setMessage(R.string.project_video_delete_message)
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> performDeleteCurrent(shot.id) }
            .show()
    }

    private fun performDeleteCurrent(shotId: Long) {
        lifecycleScope.launch {
            val result = repository.deleteShotVideo(shotId)
            if (result.dbUpdated) {
                Toast.makeText(this@VideoPlayerActivity, R.string.project_video_deleted, Toast.LENGTH_SHORT).show()
                binding.videoView.stopPlayback()
                loadVideos(projectId)
            } else {
                Toast.makeText(this@VideoPlayerActivity, R.string.project_video_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun confirmDeleteAll() {
        AlertDialog.Builder(this)
            .setTitle(R.string.project_video_delete_all)
            .setMessage(getString(R.string.project_video_bulk_delete_confirm_message, playableShots.size))
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> performDeleteAll() }
            .show()
    }

    private fun performDeleteAll() {
        lifecycleScope.launch {
            val count = repository.deleteAllStoryboardVideos(projectId, episodeId)
            Toast.makeText(
                this@VideoPlayerActivity,
                getString(R.string.project_video_bulk_deleted, count),
                Toast.LENGTH_SHORT
            ).show()
            binding.videoView.stopPlayback()
            loadVideos(projectId)
        }
    }

    private fun confirmDeleteFinal() {
        AlertDialog.Builder(this)
            .setTitle(R.string.project_final_video_delete_title)
            .setMessage(R.string.project_final_video_delete_message)
            .setNegativeButton(R.string.project_delete_cancel, null)
            .setPositiveButton(R.string.project_delete_confirm) { _, _ -> performDeleteFinal() }
            .show()
    }

    private fun performDeleteFinal() {
        lifecycleScope.launch {
            // 多集：成片挂在集上；无集号（旧版本深链接）时退回项目级删除
            val result = if (episodeId > 0L) {
                repository.deleteEpisodeFinalVideo(episodeId)
            } else {
                repository.deleteProjectFinalVideo(projectId)
            }
            if (result.dbUpdated) {
                Toast.makeText(this@VideoPlayerActivity, R.string.project_final_video_deleted, Toast.LENGTH_SHORT).show()
                finish()
            } else {
                Toast.makeText(this@VideoPlayerActivity, R.string.project_final_video_delete_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    // ────────────── 保存到相册 ──────────────

    /** 保存当前视频（成片或当前分镜）到系统相册（Android 10+ 免权限直写；更低版本先申请 WRITE_EXTERNAL_STORAGE）。 */
    private fun saveCurrentToAlbum() {
        // 分镜模式只能保存已落地的本地文件：AlbumSaver 读沙盒路径，远端 URL 需先下载
        val target = currentSaveTarget() ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_SAVE_TO_ALBUM
            )
            return
        }
        lifecycleScope.launch {
            val result = AlbumSaver.saveVideo(this@VideoPlayerActivity, target.first, target.second)
            Toast.makeText(
                this@VideoPlayerActivity,
                if (result.isSuccess) {
                    getString(R.string.project_final_video_saved_to_album)
                } else {
                    getString(
                        R.string.project_final_video_save_failed,
                        result.exceptionOrNull()?.message ?: "未知错误"
                    )
                },
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    /** 解析当前模式下要保存的 (本地路径, 相册标题)；不可保存时提示并返回 null。 */
    private fun currentSaveTarget(): Pair<String, String>? {
        if (isFinalVideoMode) {
            val path = finalVideoPath ?: return null
            return path to (finalVideoTitle ?: "final_video")
        }
        val shot = playableShots.getOrNull(currentIndex) ?: return null
        val localPath = shot.videoLocalPath?.takeIf { it.isNotBlank() && File(it).exists() }
        if (localPath == null) {
            Toast.makeText(this, R.string.project_shot_video_save_no_local, Toast.LENGTH_SHORT).show()
            return null
        }
        return localPath to getString(R.string.project_shot_video_album_title, shot.shotNumber)
    }

    @Suppress("DEPRECATION")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_SAVE_TO_ALBUM) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                saveCurrentToAlbum()
            } else {
                Toast.makeText(this, R.string.album_permission_denied, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun showNoVideos() {
        Toast.makeText(this, R.string.video_no_generated_videos, Toast.LENGTH_SHORT).show()
        finish()
    }

    companion object {
        private const val TAG = "VideoPlayerActivity"
        const val EXTRA_PROJECT_ID = "extra_project_id"
        const val EXTRA_EPISODE_ID = "extra_episode_id"
        const val EXTRA_VIDEO_PATH = "extra_video_path"
        const val EXTRA_PROJECT_TITLE = "extra_project_title"
        private const val REQUEST_SAVE_TO_ALBUM = 1001
    }
}
