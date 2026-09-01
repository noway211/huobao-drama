package com.huobao.zdrama.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import java.util.ArrayList

class StoryboardLocalDataSource(context: Context) {
    private val database = DramaLocalDatabase(context)
    private val gson = Gson()

    /** 替换某集的全部分镜：先删该集旧分镜，再批量插入。 */
    fun replaceStoryboards(projectId: Long, episodeId: Long, shots: List<StoryboardShot>) {
        val db = database.writableDatabase
        db.beginTransaction()
        try {
            db.delete(
                DramaLocalDatabase.TABLE_STORYBOARDS,
                "${DramaLocalDatabase.COL_PROJECT_ID} = ? AND ${DramaLocalDatabase.COL_EPISODE_ID} = ?",
                arrayOf(projectId.toString(), episodeId.toString())
            )
            shots.forEach { shot ->
                insertStoryboard(db, shot.copy(projectId = projectId, episodeId = episodeId))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun deleteStoryboards(projectId: Long): Int {
        return database.writableDatabase.delete(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            "${DramaLocalDatabase.COL_PROJECT_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    /** 删除某集的全部分镜（用于删除剧集 / 重新生成某集分镜）。 */
    fun deleteStoryboardsForEpisode(projectId: Long, episodeId: Long): Int {
        return database.writableDatabase.delete(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            "${DramaLocalDatabase.COL_PROJECT_ID} = ? AND ${DramaLocalDatabase.COL_EPISODE_ID} = ?",
            arrayOf(projectId.toString(), episodeId.toString())
        )
    }

    /**
     * 历史数据修复：把 episode_id 为 NULL 的分镜回填到所属项目的第一集。
     * 多集改造前（v8 migration 之后创建的）分镜 insert 时未写 episode_id，
     * 而 v8 的回填 UPDATE 只覆盖当时存量行，之后新增的仍为 NULL，
     * 导致按集查询（getStoryboards(projectId, episodeId)）漏掉这些镜头。
     * 启动时兜底执行一次，对已升级到 v12 的存量库生效。
     */
    fun backfillEpisodeIds() {
        database.writableDatabase.execSQL(
            """
            UPDATE ${DramaLocalDatabase.TABLE_STORYBOARDS}
            SET ${DramaLocalDatabase.COL_EPISODE_ID} = (
                SELECT ${DramaLocalDatabase.COL_ID} FROM ${DramaLocalDatabase.TABLE_EPISODES}
                WHERE ${DramaLocalDatabase.TABLE_EPISODES}.${DramaLocalDatabase.COL_PROJECT_ID} =
                      ${DramaLocalDatabase.TABLE_STORYBOARDS}.${DramaLocalDatabase.COL_PROJECT_ID}
                ORDER BY ${DramaLocalDatabase.COL_EPISODE_NUMBER} ASC
                LIMIT 1
            )
            WHERE ${DramaLocalDatabase.COL_EPISODE_ID} IS NULL
            """
        )
    }

    /** 查询项目全部分镜（项目级视图，兼容旧调用）。 */
    fun getStoryboards(projectId: Long): List<StoryboardShot> {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            null,
            "${DramaLocalDatabase.COL_PROJECT_ID} = ?",
            arrayOf(projectId.toString()),
            null,
            null,
            "${DramaLocalDatabase.COL_SHOT_NUMBER} ASC"
        )
        return cursor.use { readShots(it) }
    }

    /** 查询某集的全部分镜（多集支持的主查询路径）。 */
    fun getStoryboards(projectId: Long, episodeId: Long): List<StoryboardShot> {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            null,
            "${DramaLocalDatabase.COL_PROJECT_ID} = ? AND ${DramaLocalDatabase.COL_EPISODE_ID} = ?",
            arrayOf(projectId.toString(), episodeId.toString()),
            null,
            null,
            "${DramaLocalDatabase.COL_SHOT_NUMBER} ASC"
        )
        return cursor.use { readShots(it) }
    }

    fun updateShotImage(
        shotId: Long,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_IMAGE_STATUS, imageStatus.name)
            put(DramaLocalDatabase.COL_IMAGE_URL, imageUrl)
            put(DramaLocalDatabase.COL_IMAGE_LOCAL_PATH, imageLocalPath)
            put(DramaLocalDatabase.COL_IMAGE_ERROR_MESSAGE, imageErrorMessage)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(shotId.toString())
        )
    }

    fun updateShotVideo(
        shotId: Long,
        videoStatus: AssetStatus,
        videoTaskId: String?,
        videoUrl: String?,
        videoLocalPath: String?,
        videoErrorMessage: String?
    ): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_VIDEO_STATUS, videoStatus.name)
            put(DramaLocalDatabase.COL_VIDEO_TASK_ID, videoTaskId)
            put(DramaLocalDatabase.COL_VIDEO_URL, videoUrl)
            put(DramaLocalDatabase.COL_VIDEO_LOCAL_PATH, videoLocalPath)
            put(DramaLocalDatabase.COL_VIDEO_ERROR_MESSAGE, videoErrorMessage)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(shotId.toString())
        )
    }

    fun updateShotImagePrompt(shotId: Long, newPrompt: String): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_IMAGE_PROMPT, newPrompt)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(shotId.toString())
        )
    }

    fun updateShotVideoPrompt(shotId: Long, newPrompt: String): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_VIDEO_PROMPT, newPrompt)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(shotId.toString())
        )
    }

    /**
     * 更新分镜的角色绑定。characterIds 为 JSON 字符串：
     * 数字 ID 数组（用户绑定）或名字字符串数组（LLM 初始生成）；空绑定传 "" 或 null。
     */
    fun updateShotCharacterIds(shotId: Long, characterIds: String?): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_CHARACTER_IDS, characterIds)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_STORYBOARDS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(shotId.toString())
        )
    }

    private fun insertStoryboard(db: SQLiteDatabase, shot: StoryboardShot): Long {
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_PROJECT_ID, shot.projectId)
            put(DramaLocalDatabase.COL_EPISODE_ID, shot.episodeId)
            put(DramaLocalDatabase.COL_SHOT_NUMBER, shot.shotNumber)
            put(DramaLocalDatabase.COL_SCENE, shot.scene)
            put(DramaLocalDatabase.COL_ACTION, shot.action)
            put(DramaLocalDatabase.COL_DIALOGUE, shot.dialogue)
            put(DramaLocalDatabase.COL_CAMERA, shot.camera)
            put(DramaLocalDatabase.COL_IMAGE_PROMPT, shot.imagePrompt)
            put(DramaLocalDatabase.COL_VIDEO_PROMPT, shot.videoPrompt)
            put(DramaLocalDatabase.COL_DURATION_SECONDS, shot.durationSeconds)
            put(DramaLocalDatabase.COL_CHARACTER_NAMES, encodeCharacterNames(shot.characterNames))
            // characterIds 为空时回退写入 characterNames 的 JSON，保证新列始终有值（与 Harmony 语义一致）
            put(DramaLocalDatabase.COL_CHARACTER_IDS, shot.characterIds ?: encodeCharacterNames(shot.characterNames))
            put(DramaLocalDatabase.COL_IMAGE_STATUS, shot.imageStatus.name)
            put(DramaLocalDatabase.COL_IMAGE_URL, shot.imageUrl)
            put(DramaLocalDatabase.COL_IMAGE_LOCAL_PATH, shot.imageLocalPath)
            put(DramaLocalDatabase.COL_IMAGE_ERROR_MESSAGE, shot.imageErrorMessage)
            put(DramaLocalDatabase.COL_VIDEO_STATUS, shot.videoStatus.name)
            put(DramaLocalDatabase.COL_VIDEO_TASK_ID, shot.videoTaskId)
            put(DramaLocalDatabase.COL_VIDEO_URL, shot.videoUrl)
            put(DramaLocalDatabase.COL_VIDEO_LOCAL_PATH, shot.videoLocalPath)
            put(DramaLocalDatabase.COL_VIDEO_ERROR_MESSAGE, shot.videoErrorMessage)
            put(DramaLocalDatabase.COL_CREATED_AT, now)
            put(DramaLocalDatabase.COL_UPDATED_AT, now)
        }
        return db.insert(DramaLocalDatabase.TABLE_STORYBOARDS, null, values)
    }

    private fun readShots(cursor: Cursor): List<StoryboardShot> {
        val shots = mutableListOf<StoryboardShot>()
        while (cursor.moveToNext()) {
            val names = decodeCharacterNames(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_NAMES)))
            // 旧数据 character_ids 列为 NULL 时回退到 character_names 的 JSON，保证 domain 层永远有绑定值
            val rawCharacterIds = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_IDS))
            shots.add(
                StoryboardShot(
                    id = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ID)),
                    projectId = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_PROJECT_ID)),
                    episodeId = readNullableLong(cursor, DramaLocalDatabase.COL_EPISODE_ID),
                    shotNumber = cursor.getInt(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SHOT_NUMBER)),
                    scene = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE)),
                    action = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ACTION)),
                    dialogue = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_DIALOGUE)),
                    camera = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CAMERA)),
                    imagePrompt = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_IMAGE_PROMPT)),
                    videoPrompt = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_VIDEO_PROMPT)),
                    durationSeconds = cursor.getInt(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_DURATION_SECONDS)),
                    characterNames = names,
                    characterIds = rawCharacterIds ?: encodeCharacterNames(names),
                    imageStatus = parseAssetStatus(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_IMAGE_STATUS))),
                    imageUrl = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_IMAGE_URL)),
                    imageLocalPath = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_IMAGE_LOCAL_PATH)),
                    imageErrorMessage = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_IMAGE_ERROR_MESSAGE)),
                    videoStatus = parseAssetStatus(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_VIDEO_STATUS))),
                    videoTaskId = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_VIDEO_TASK_ID)),
                    videoUrl = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_VIDEO_URL)),
                    videoLocalPath = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_VIDEO_LOCAL_PATH)),
                    videoErrorMessage = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_VIDEO_ERROR_MESSAGE)),
                    createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CREATED_AT)),
                    updatedAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_UPDATED_AT))
                )
            )
        }
        return shots
    }

    private fun parseAssetStatus(value: String?): AssetStatus {
        return runCatching { AssetStatus.valueOf(value ?: AssetStatus.PENDING.name) }
            .getOrDefault(AssetStatus.PENDING)
    }

    /** 读取可空整数列（如 episode_id，旧数据可能为 NULL）。 */
    private fun readNullableLong(cursor: Cursor, column: String): Long? {
        val index = cursor.getColumnIndexOrThrow(column)
        return if (cursor.isNull(index)) null else cursor.getLong(index)
    }

    private fun encodeCharacterNames(names: List<String>): String? {
        if (names.isEmpty()) return null
        return gson.toJson(names)
    }

    private fun decodeCharacterNames(json: String?): List<String> {
        if (json.isNullOrBlank()) return emptyList()
        val type = object : TypeToken<ArrayList<String>>() {}.type
        return runCatching { gson.fromJson<ArrayList<String>>(json, type) }
            .getOrNull() ?: emptyList()
    }
}
