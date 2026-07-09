package com.huobao.zdrama.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "skill_configs")
data class SkillConfigEntity(
    @PrimaryKey val id: String,
    val name: String,
    val version: String,
    val required: Boolean,
    val enabled: Boolean,
    val modelType: String,
    val temperature: Double,
    val maxOutputTokens: Int,
    val outputMode: String,
    val promptTemplate: String
)
