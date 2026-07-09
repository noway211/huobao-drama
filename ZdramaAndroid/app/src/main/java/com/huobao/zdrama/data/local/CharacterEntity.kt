package com.huobao.zdrama.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "characters")
data class CharacterEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val projectId: Long,
    val name: String,
    val role: String,
    val personality: String,
    val description: String,
    val appearance: String,
    val visualPrompt: String
)
