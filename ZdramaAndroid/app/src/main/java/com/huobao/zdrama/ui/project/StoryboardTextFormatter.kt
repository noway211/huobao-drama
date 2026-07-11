package com.huobao.zdrama.ui.project

import android.content.Context
import com.huobao.zdrama.R
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.StoryboardShot

/** 分镜文本格式化,详情页与分镜查看页共用。 */
object StoryboardTextFormatter {
    fun format(context: Context, storyboards: List<StoryboardShot>): String {
        return storyboards.joinToString(separator = "\n\n") { shot ->
            buildString {
                append("#").append(shot.shotNumber).append("  ").append(shot.scene).append('\n')
                append(context.getString(R.string.project_action_label)).append("：").append(shot.action).append('\n')
                append(context.getString(R.string.project_dialogue_label)).append("：").append(shot.dialogue).append('\n')
                append(context.getString(R.string.project_camera_label)).append("：").append(shot.camera).append('\n')
                append(context.getString(R.string.project_image_status_label)).append("：").append(displayAssetStatus(context, shot.imageStatus)).append('\n')
                shot.imageUrl?.takeIf { it.isNotBlank() }?.let { imageUrl ->
                    append(context.getString(R.string.project_image_url_label)).append("：").append(imageUrl).append('\n')
                }
                shot.imageLocalPath?.takeIf { it.isNotBlank() }?.let { imageLocalPath ->
                    append(context.getString(R.string.project_image_local_path_label)).append("：").append(imageLocalPath).append('\n')
                }
                shot.imageErrorMessage?.takeIf { it.isNotBlank() }?.let { error ->
                    append(context.getString(R.string.project_error_label)).append("：").append(error).append('\n')
                }
                append(context.getString(R.string.project_video_status_label)).append("：").append(displayAssetStatus(context, shot.videoStatus)).append('\n')
                shot.videoTaskId?.takeIf { it.isNotBlank() }?.let { taskId ->
                    append(context.getString(R.string.project_video_task_label)).append("：").append(taskId).append('\n')
                }
                shot.videoUrl?.takeIf { it.isNotBlank() }?.let { videoUrl ->
                    append(context.getString(R.string.project_video_url_label)).append("：").append(videoUrl).append('\n')
                }
                shot.videoLocalPath?.takeIf { it.isNotBlank() }?.let { videoLocalPath ->
                    append(context.getString(R.string.project_video_local_path_label)).append("：").append(videoLocalPath).append('\n')
                }
                shot.videoErrorMessage?.takeIf { it.isNotBlank() }?.let { error ->
                    append(context.getString(R.string.project_error_label)).append("：").append(error).append('\n')
                }
                append(context.getString(R.string.project_image_prompt_label)).append("：").append(shot.imagePrompt).append('\n')
                append(context.getString(R.string.project_video_prompt_label)).append("：").append(shot.videoPrompt)
            }
        }
    }

    private fun displayAssetStatus(context: Context, status: AssetStatus): String {
        return context.getString(
            when (status) {
                AssetStatus.PENDING -> R.string.asset_pending
                AssetStatus.PROCESSING -> R.string.asset_processing
                AssetStatus.COMPLETED -> R.string.asset_completed
                AssetStatus.FAILED -> R.string.asset_failed
            }
        )
    }
}
