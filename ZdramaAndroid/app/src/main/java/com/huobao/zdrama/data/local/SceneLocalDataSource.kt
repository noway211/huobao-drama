package com.huobao.zdrama.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.util.Log
import com.huobao.zdrama.domain.model.Scene

open class SceneLocalDataSource(private val database: DramaLocalDatabase?) {
    constructor(context: Context) : this(DramaLocalDatabase(context))

    private fun db(): DramaLocalDatabase = database ?: error("Scene database is not available")

    /**
     * 按地点 + 时间去重写入（对齐 backend save_dedup_scenes）：
     * - 地点和时间都相同：UPDATE 氛围和提示词，保留主键
     * - 否则 INSERT 新行（同地点不同时间也是新场景）
     * 本集未提到的已有场景不删除。
     */
    open fun upsertScenes(projectId: Long, scenes: List<Scene>) {
        val db = db().writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            val existing = readScenes(
                db.query(
                    DramaLocalDatabase.TABLE_SCENES,
                    null,
                    "${DramaLocalDatabase.COL_SCENE_PROJECT_ID} = ?",
                    arrayOf(projectId.toString()),
                    null,
                    null,
                    "${DramaLocalDatabase.COL_ID} ASC"
                )
            )
            val merged = SceneDeduper.upsert(existing, scenes.map { it.copy(projectId = projectId) }, now)
            merged.forEach { scene ->
                val alreadyStored = existing.any { it.id == scene.id }
                if (alreadyStored) {
                    updateSceneText(db, scene.id, scene, scene.updatedAt)
                    Log.i(TAG, "upsert UPDATE id=${scene.id} location=${scene.location} time=${scene.time}")
                } else {
                    val newId = insertScene(db, scene.copy(id = 0L))
                    Log.i(TAG, "upsert INSERT location=${scene.location} time=${scene.time} newId=$newId")
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    open fun getScenes(projectId: Long): List<Scene> {
        val cursor = db().readableDatabase.query(
            DramaLocalDatabase.TABLE_SCENES,
            null,
            "${DramaLocalDatabase.COL_SCENE_PROJECT_ID} = ?",
            arrayOf(projectId.toString()),
            null,
            null,
            "${DramaLocalDatabase.COL_ID} ASC"
        )
        return cursor.use { readScenes(it) }
    }

    fun deleteScenesForProject(projectId: Long): Int {
        return db().writableDatabase.delete(
            DramaLocalDatabase.TABLE_SCENES,
            "${DramaLocalDatabase.COL_SCENE_PROJECT_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    private fun updateSceneText(
        db: android.database.sqlite.SQLiteDatabase,
        sceneId: Long,
        scene: Scene,
        updatedAt: Long
    ) {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_SCENE_ATMOSPHERE, scene.atmosphere)
            put(DramaLocalDatabase.COL_SCENE_PROMPT, scene.prompt)
            put(DramaLocalDatabase.COL_UPDATED_AT, updatedAt)
        }
        db.update(
            DramaLocalDatabase.TABLE_SCENES,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(sceneId.toString())
        )
    }

    private fun insertScene(db: android.database.sqlite.SQLiteDatabase, scene: Scene): Long {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_SCENE_PROJECT_ID, scene.projectId)
            if (scene.episodeId != null) put(DramaLocalDatabase.COL_SCENE_EPISODE_ID, scene.episodeId)
            put(DramaLocalDatabase.COL_SCENE_LOCATION, scene.location)
            put(DramaLocalDatabase.COL_SCENE_TIME, scene.time)
            put(DramaLocalDatabase.COL_SCENE_ATMOSPHERE, scene.atmosphere)
            put(DramaLocalDatabase.COL_SCENE_PROMPT, scene.prompt)
            put(DramaLocalDatabase.COL_CREATED_AT, scene.createdAt)
            put(DramaLocalDatabase.COL_UPDATED_AT, scene.updatedAt)
        }
        return db.insert(DramaLocalDatabase.TABLE_SCENES, null, values)
    }

    private fun readScenes(cursor: Cursor): List<Scene> {
        val result = mutableListOf<Scene>()
        while (cursor.moveToNext()) {
            result.add(
                Scene(
                    id = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ID)),
                    projectId = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE_PROJECT_ID)),
                    episodeId = cursor.getLongOrNull(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE_EPISODE_ID)),
                    location = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE_LOCATION)) ?: "",
                    time = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE_TIME)) ?: "",
                    atmosphere = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE_ATMOSPHERE)) ?: "",
                    prompt = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SCENE_PROMPT)) ?: "",
                    createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CREATED_AT)),
                    updatedAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_UPDATED_AT))
                )
            )
        }
        return result
    }

    private fun Cursor.getLongOrNull(index: Int): Long? {
        if (isNull(index)) return null
        return getLong(index)
    }

    companion object {
        private const val TAG = "SceneLocalDS"
    }
}
