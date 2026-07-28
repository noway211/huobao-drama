package com.huobao.zdrama.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import com.huobao.zdrama.domain.model.Episode
import com.huobao.zdrama.domain.model.EpisodeStatus

class EpisodeLocalDataSource(context: Context) {
    private val database = DramaLocalDatabase(context)

    fun insertEpisode(episode: Episode): Long {
        val now = if (episode.createdAt > 0L) episode.createdAt else System.currentTimeMillis()
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_PROJECT_ID, episode.projectId)
            put(DramaLocalDatabase.COL_EPISODE_NUMBER, episode.episodeNumber)
            put(DramaLocalDatabase.COL_EPISODE_TITLE, episode.title)
            put(DramaLocalDatabase.COL_EPISODE_CONTENT, episode.content)
            put(DramaLocalDatabase.COL_EPISODE_SCRIPT_CONTENT, episode.scriptContent)
            put(DramaLocalDatabase.COL_EPISODE_STATUS, episode.status.name)
            put(DramaLocalDatabase.COL_CREATED_AT, now)
            put(DramaLocalDatabase.COL_UPDATED_AT, now)
        }
        return database.writableDatabase.insert(DramaLocalDatabase.TABLE_EPISODES, null, values)
    }

    fun getEpisodeForProject(projectId: Long): Episode? {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_EPISODES,
            null,
            "${DramaLocalDatabase.COL_PROJECT_ID} = ?",
            arrayOf(projectId.toString()),
            null,
            null,
            "${DramaLocalDatabase.COL_EPISODE_NUMBER} ASC",
            "1"
        )
        return cursor.use {
            if (it.moveToFirst()) readEpisode(it) else null
        }
    }

    fun getEpisodeById(episodeId: Long): Episode? {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_EPISODES,
            null,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(episodeId.toString()),
            null,
            null,
            null,
            "1"
        )
        return cursor.use {
            if (it.moveToFirst()) readEpisode(it) else null
        }
    }

    fun updateEpisodeContent(episodeId: Long, content: String?): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_EPISODE_CONTENT, content)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_EPISODES,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(episodeId.toString())
        )
    }

    fun updateEpisodeScriptContent(episodeId: Long, scriptContent: String?, status: EpisodeStatus): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_EPISODE_SCRIPT_CONTENT, scriptContent)
            put(DramaLocalDatabase.COL_EPISODE_STATUS, status.name)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_EPISODES,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(episodeId.toString())
        )
    }

    fun deleteEpisodesForProject(projectId: Long): Int {
        return database.writableDatabase.delete(
            DramaLocalDatabase.TABLE_EPISODES,
            "${DramaLocalDatabase.COL_PROJECT_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    private fun readEpisode(cursor: Cursor): Episode {
        return Episode(
            id = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ID)),
            projectId = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_PROJECT_ID)),
            episodeNumber = cursor.getInt(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_EPISODE_NUMBER)),
            title = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_EPISODE_TITLE)) ?: "",
            content = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_EPISODE_CONTENT)),
            scriptContent = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_EPISODE_SCRIPT_CONTENT)),
            status = parseEpisodeStatus(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_EPISODE_STATUS))),
            createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CREATED_AT)),
            updatedAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_UPDATED_AT))
        )
    }

    private fun parseEpisodeStatus(value: String?): EpisodeStatus {
        return runCatching { EpisodeStatus.valueOf(value ?: EpisodeStatus.DRAFT.name) }
            .getOrDefault(EpisodeStatus.DRAFT)
    }
}
