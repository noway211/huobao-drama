package com.huobao.zdrama.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "storyboards")
data class StoryboardEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val projectId: Long,
    val index: Int,
    val title: String,
    val description: String,
    val sceneName: String,
    val charactersJson: String,
    val imagePrompt: String,
    val videoPrompt: String,
    val durationSeconds: Int,
    val imageStatus: String,
    val imageTaskId: String?,
    val imageUrl: String?,
    val localImagePath: String?,
    val videoStatus: String,
    val videoTaskId: String?,
    val videoUrl: String?,
    val localVideoPath: String?,
    val errorMessage: String?
)
