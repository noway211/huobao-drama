package com.huobao.zdrama.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "projects")
data class ProjectEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val title: String,
    val prompt: String,
    val style: String,
    val targetAudience: String,
    val aspectRatio: String,
    val shotCount: Int,
    val shotDurationSeconds: Int,
    val status: String,
    val currentStage: String,
    val errorMessage: String?,
    val createdAt: Long,
    val updatedAt: Long
)
