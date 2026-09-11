package com.huobao.zdrama.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character

class CharacterLocalDataSource(context: Context) {
    private val database = DramaLocalDatabase(context)

    /**
     * 全量替换项目角色：先删后插。仅用于需要清空重建的场景（当前提取角色已改走 [upsertCharacters]）。
     */
    fun replaceCharacters(projectId: Long, characters: List<Character>) {
        val db = database.writableDatabase
        db.beginTransaction()
        try {
            db.delete(
                DramaLocalDatabase.TABLE_CHARACTERS,
                "${DramaLocalDatabase.COL_CHARACTER_PROJECT_ID} = ?",
                arrayOf(projectId.toString())
            )
            val now = System.currentTimeMillis()
            characters.forEach { ch -> insertCharacter(db, ch.copy(projectId = projectId, createdAt = now, updatedAt = now)) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /**
     * 增量写入角色（对齐 backend save_dedup_characters）：
     * - id > 0：UPDATE 文字字段，保留主键 / 立绘 / createdAt（分镜 characterIds 数字绑定不失效）
     * - id == 0：INSERT 新行
     * 本集未提到的已有角色**不删除**。
     */
    fun upsertCharacters(projectId: Long, characters: List<Character>) {
        val db = database.writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            characters.forEach { ch ->
                val withProject = ch.copy(projectId = projectId, updatedAt = now)
                if (withProject.id > 0L) {
                    updateCharacterText(db, withProject)
                } else {
                    insertCharacter(db, withProject.copy(createdAt = now))
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** 更新角色文字字段（role/description/appearance/personality），不动立绘 / 主键 / episodeId。 */
    private fun updateCharacterText(db: android.database.sqlite.SQLiteDatabase, ch: Character) {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_CHARACTER_ROLE, ch.role)
            put(DramaLocalDatabase.COL_CHARACTER_DESCRIPTION, ch.description)
            put(DramaLocalDatabase.COL_CHARACTER_APPEARANCE, ch.appearance)
            put(DramaLocalDatabase.COL_CHARACTER_PERSONALITY, ch.personality)
            put(DramaLocalDatabase.COL_UPDATED_AT, ch.updatedAt)
        }
        db.update(
            DramaLocalDatabase.TABLE_CHARACTERS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(ch.id.toString())
        )
    }

    fun getCharacters(projectId: Long): List<Character> {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_CHARACTERS,
            null,
            "${DramaLocalDatabase.COL_CHARACTER_PROJECT_ID} = ?",
            arrayOf(projectId.toString()),
            null,
            null,
            "${DramaLocalDatabase.COL_ID} ASC"
        )
        return cursor.use { readCharacters(it) }
    }

    fun getCharacter(characterId: Long): Character? {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_CHARACTERS,
            null,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(characterId.toString()),
            null,
            null,
            null,
            "1"
        )
        return cursor.use {
            if (it.moveToFirst()) readCharacters(it).firstOrNull() else null
        }
    }

    fun deleteCharactersForProject(projectId: Long): Int {
        return database.writableDatabase.delete(
            DramaLocalDatabase.TABLE_CHARACTERS,
            "${DramaLocalDatabase.COL_CHARACTER_PROJECT_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    fun updateCharacterImage(
        characterId: Long,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_STATUS, imageStatus.name)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_URL, imageUrl)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_LOCAL_PATH, imageLocalPath)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_ERROR_MESSAGE, imageErrorMessage)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_CHARACTERS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(characterId.toString())
        )
    }

    fun updateCharacterAppearance(characterId: Long, appearance: String): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_CHARACTER_APPEARANCE, appearance)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_CHARACTERS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(characterId.toString())
        )
    }

    private fun insertCharacter(db: android.database.sqlite.SQLiteDatabase, ch: Character): Long {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_CHARACTER_PROJECT_ID, ch.projectId)
            if (ch.episodeId != null) put(DramaLocalDatabase.COL_CHARACTER_EPISODE_ID, ch.episodeId)
            put(DramaLocalDatabase.COL_CHARACTER_NAME, ch.name)
            put(DramaLocalDatabase.COL_CHARACTER_ROLE, ch.role)
            put(DramaLocalDatabase.COL_CHARACTER_DESCRIPTION, ch.description)
            put(DramaLocalDatabase.COL_CHARACTER_APPEARANCE, ch.appearance)
            put(DramaLocalDatabase.COL_CHARACTER_PERSONALITY, ch.personality)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_STATUS, ch.imageStatus.name)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_URL, ch.imageUrl)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_LOCAL_PATH, ch.imageLocalPath)
            put(DramaLocalDatabase.COL_CHARACTER_IMAGE_ERROR_MESSAGE, ch.imageErrorMessage)
            put(DramaLocalDatabase.COL_CREATED_AT, ch.createdAt)
            put(DramaLocalDatabase.COL_UPDATED_AT, ch.updatedAt)
        }
        return db.insert(DramaLocalDatabase.TABLE_CHARACTERS, null, values)
    }

    private fun readCharacters(cursor: Cursor): List<Character> {
        val result = mutableListOf<Character>()
        while (cursor.moveToNext()) {
            result.add(
                Character(
                    id = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ID)),
                    projectId = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_PROJECT_ID)),
                    episodeId = cursor.getLongOrNull(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_EPISODE_ID)),
                    name = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_NAME)) ?: "",
                    role = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_ROLE)) ?: "",
                    description = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_DESCRIPTION)) ?: "",
                    appearance = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_APPEARANCE)) ?: "",
                    personality = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_PERSONALITY)) ?: "",
                    imageStatus = parseAssetStatus(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_IMAGE_STATUS))),
                    imageUrl = cursor.getStringOrNull(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_IMAGE_URL)),
                    imageLocalPath = cursor.getStringOrNull(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_IMAGE_LOCAL_PATH)),
                    imageErrorMessage = cursor.getStringOrNull(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CHARACTER_IMAGE_ERROR_MESSAGE)),
                    createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CREATED_AT)),
                    updatedAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_UPDATED_AT))
                )
            )
        }
        return result
    }

    private fun parseAssetStatus(value: String?): AssetStatus {
        return runCatching { AssetStatus.valueOf(value ?: AssetStatus.PENDING.name) }
            .getOrDefault(AssetStatus.PENDING)
    }

    private fun Cursor.getStringOrNull(index: Int): String? {
        if (isNull(index)) return null
        return getString(index)
    }

    private fun Cursor.getLongOrNull(index: Int): Long? {
        if (isNull(index)) return null
        return getLong(index)
    }
}
