package com.huobao.zdrama.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "scenes")
data class SceneEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val projectId: Long,
    val name: String,
    val description: String,
    val atmosphere: String,
    val visualPrompt: String
)
