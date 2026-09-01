package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.domain.model.StoryboardShot

class GetStoryboardsUseCase(
    private val dramaRepository: DramaRepository
) {
    suspend fun execute(projectId: Long): List<StoryboardShot> {
        return dramaRepository.getStoryboards(projectId)
    }

    /** 多集支持：查询某集的分镜。 */
    suspend fun execute(projectId: Long, episodeId: Long): List<StoryboardShot> {
        return dramaRepository.getStoryboards(projectId, episodeId)
    }
}
