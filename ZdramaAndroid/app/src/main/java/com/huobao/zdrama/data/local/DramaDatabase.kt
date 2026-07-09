package com.huobao.zdrama.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [
        ProjectEntity::class,
        CharacterEntity::class,
        SceneEntity::class,
        StoryboardEntity::class,
        SkillConfigEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class DramaDatabase : RoomDatabase() {
    abstract fun dramaDao(): DramaDao
}
