package com.huobao.zdrama.data.repository

import com.huobao.zdrama.data.local.DramaDao
import com.huobao.zdrama.data.local.StoryboardEntity

class GenerationRepository(
    private val dramaDao: DramaDao
) {
    suspend fun getStoryboards(projectId: Long): List<StoryboardEntity> {
        return dramaDao.getStoryboards(projectId)
    }
}
