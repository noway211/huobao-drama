package com.huobao.zdrama.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character

class CharacterLocalDataSource(context: Context) {
    private val database = DramaLocalDatabase(context)

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
