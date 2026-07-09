package com.huobao.zdrama.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface DramaDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertProject(project: ProjectEntity): Long

    @Query("SELECT * FROM projects ORDER BY updatedAt DESC")
    suspend fun getProjects(): List<ProjectEntity>

    @Query("SELECT * FROM storyboards WHERE projectId = :projectId ORDER BY `index` ASC")
    suspend fun getStoryboards(projectId: Long): List<StoryboardEntity>
}
