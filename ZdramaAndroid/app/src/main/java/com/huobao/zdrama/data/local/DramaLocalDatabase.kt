package com.huobao.zdrama.data.local

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class DramaLocalDatabase(context: Context) : SQLiteOpenHelper(
    context.applicationContext,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(SQL_CREATE_PROJECTS)
        db.execSQL(SQL_CREATE_STORYBOARDS)
        db.execSQL(SQL_CREATE_EPISODES)
        db.execSQL(SQL_CREATE_CHARACTERS)
        db.execSQL(SQL_CREATE_INDEX_CHARACTERS_PROJECT_ID)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE $TABLE_PROJECTS ADD COLUMN $COL_GENERATED_SCRIPT TEXT")
        }
        if (oldVersion < 3) {
            db.execSQL(SQL_CREATE_STORYBOARDS)
        } else {
            if (oldVersion < 4) {
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_IMAGE_STATUS TEXT NOT NULL DEFAULT 'PENDING'")
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_IMAGE_URL TEXT")
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_IMAGE_ERROR_MESSAGE TEXT")
            }
            if (oldVersion < 5) {
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_VIDEO_STATUS TEXT NOT NULL DEFAULT 'PENDING'")
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_VIDEO_TASK_ID TEXT")
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_VIDEO_URL TEXT")
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_VIDEO_ERROR_MESSAGE TEXT")
            }
            if (oldVersion < 6) {
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_IMAGE_LOCAL_PATH TEXT")
                db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_VIDEO_LOCAL_PATH TEXT")
            }
        }
        if (oldVersion < 7) {
            db.execSQL("ALTER TABLE $TABLE_PROJECTS ADD COLUMN $COL_FINAL_VIDEO_STATUS TEXT NOT NULL DEFAULT 'PENDING'")
            db.execSQL("ALTER TABLE $TABLE_PROJECTS ADD COLUMN $COL_FINAL_VIDEO_LOCAL_PATH TEXT")
            db.execSQL("ALTER TABLE $TABLE_PROJECTS ADD COLUMN $COL_FINAL_VIDEO_ERROR_MESSAGE TEXT")
        }
        if (oldVersion < 8) {
            db.execSQL(SQL_CREATE_EPISODES)
            db.execSQL("""
                INSERT INTO $TABLE_EPISODES ($COL_PROJECT_ID, $COL_EPISODE_NUMBER, $COL_EPISODE_TITLE, $COL_EPISODE_CONTENT, $COL_EPISODE_SCRIPT_CONTENT, $COL_EPISODE_STATUS, $COL_CREATED_AT, $COL_UPDATED_AT)
                SELECT $COL_ID, 1, $COL_TITLE, $COL_PROMPT, $COL_GENERATED_SCRIPT,
                    CASE WHEN $COL_GENERATED_SCRIPT IS NOT NULL THEN 'COMPLETED' ELSE 'DRAFT' END,
                    $COL_CREATED_AT, $COL_UPDATED_AT
                FROM $TABLE_PROJECTS
            """)
            db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_EPISODE_ID INTEGER")
            db.execSQL("""
                UPDATE $TABLE_STORYBOARDS
                SET $COL_EPISODE_ID = (
                    SELECT $COL_ID FROM $TABLE_EPISODES
                    WHERE $TABLE_EPISODES.$COL_PROJECT_ID = $TABLE_STORYBOARDS.$COL_PROJECT_ID
                    LIMIT 1
                )
            """)
        }
        if (oldVersion < 9) {
            db.execSQL(SQL_CREATE_CHARACTERS)
            db.execSQL(SQL_CREATE_INDEX_CHARACTERS_PROJECT_ID)
        }
        if (oldVersion < 10) {
            db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_CHARACTER_NAMES TEXT")
        }
        if (oldVersion < 11) {
            db.execSQL("ALTER TABLE $TABLE_STORYBOARDS ADD COLUMN $COL_CHARACTER_IDS TEXT")
        }
    }

    companion object {
        private const val DATABASE_NAME = "zdrama.db"
        private const val DATABASE_VERSION = 11

        const val TABLE_PROJECTS = "projects"
        const val COL_ID = "id"
        const val COL_TITLE = "title"
        const val COL_PROMPT = "prompt"
        const val COL_STYLE = "style"
        const val COL_TARGET_AUDIENCE = "target_audience"
        const val COL_ASPECT_RATIO = "aspect_ratio"
        const val COL_SHOT_COUNT = "shot_count"
        const val COL_SHOT_DURATION_SECONDS = "shot_duration_seconds"
        const val COL_STATUS = "status"
        const val COL_CURRENT_STAGE = "current_stage"
        const val COL_ERROR_MESSAGE = "error_message"
        const val COL_GENERATED_SCRIPT = "generated_script"
        const val COL_FINAL_VIDEO_STATUS = "final_video_status"
        const val COL_FINAL_VIDEO_LOCAL_PATH = "final_video_local_path"
        const val COL_FINAL_VIDEO_ERROR_MESSAGE = "final_video_error_message"
        const val COL_CREATED_AT = "created_at"
        const val COL_UPDATED_AT = "updated_at"

        const val TABLE_STORYBOARDS = "storyboards"
        const val COL_PROJECT_ID = "project_id"
        const val COL_SHOT_NUMBER = "shot_number"
        const val COL_SCENE = "scene"
        const val COL_ACTION = "action"
        const val COL_DIALOGUE = "dialogue"
        const val COL_CAMERA = "camera"
        const val COL_IMAGE_PROMPT = "image_prompt"
        const val COL_VIDEO_PROMPT = "video_prompt"
        const val COL_DURATION_SECONDS = "duration_seconds"
        const val COL_IMAGE_STATUS = "image_status"
        const val COL_IMAGE_URL = "image_url"
        const val COL_IMAGE_LOCAL_PATH = "image_local_path"
        const val COL_IMAGE_ERROR_MESSAGE = "image_error_message"
        const val COL_VIDEO_STATUS = "video_status"
        const val COL_VIDEO_TASK_ID = "video_task_id"
        const val COL_VIDEO_URL = "video_url"
        const val COL_VIDEO_LOCAL_PATH = "video_local_path"
        const val COL_VIDEO_ERROR_MESSAGE = "video_error_message"
        const val COL_CHARACTER_NAMES = "character_names"
        const val COL_CHARACTER_IDS = "character_ids"

        const val TABLE_EPISODES = "episodes"
        const val COL_EPISODE_ID = "episode_id"
        const val COL_EPISODE_NUMBER = "episode_number"
        const val COL_EPISODE_TITLE = "episode_title"
        const val COL_EPISODE_CONTENT = "content"
        const val COL_EPISODE_SCRIPT_CONTENT = "script_content"
        const val COL_EPISODE_STATUS = "episode_status"

        const val TABLE_CHARACTERS = "characters"
        const val COL_CHARACTER_PROJECT_ID = "project_id"
        const val COL_CHARACTER_EPISODE_ID = "episode_id"
        const val COL_CHARACTER_NAME = "name"
        const val COL_CHARACTER_ROLE = "role"
        const val COL_CHARACTER_DESCRIPTION = "description"
        const val COL_CHARACTER_APPEARANCE = "appearance"
        const val COL_CHARACTER_PERSONALITY = "personality"
        const val COL_CHARACTER_IMAGE_STATUS = "image_status"
        const val COL_CHARACTER_IMAGE_URL = "image_url"
        const val COL_CHARACTER_IMAGE_LOCAL_PATH = "image_local_path"
        const val COL_CHARACTER_IMAGE_ERROR_MESSAGE = "image_error_message"

        private const val SQL_CREATE_PROJECTS = """
            CREATE TABLE IF NOT EXISTS $TABLE_PROJECTS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_TITLE TEXT NOT NULL,
                $COL_PROMPT TEXT NOT NULL,
                $COL_STYLE TEXT NOT NULL,
                $COL_TARGET_AUDIENCE TEXT NOT NULL,
                $COL_ASPECT_RATIO TEXT NOT NULL,
                $COL_SHOT_COUNT INTEGER NOT NULL,
                $COL_SHOT_DURATION_SECONDS INTEGER NOT NULL,
                $COL_STATUS TEXT NOT NULL,
                $COL_CURRENT_STAGE TEXT NOT NULL,
                $COL_ERROR_MESSAGE TEXT,
                $COL_GENERATED_SCRIPT TEXT,
                $COL_FINAL_VIDEO_STATUS TEXT NOT NULL DEFAULT 'PENDING',
                $COL_FINAL_VIDEO_LOCAL_PATH TEXT,
                $COL_FINAL_VIDEO_ERROR_MESSAGE TEXT,
                $COL_CREATED_AT INTEGER NOT NULL,
                $COL_UPDATED_AT INTEGER NOT NULL
            )
        """

        private const val SQL_CREATE_STORYBOARDS = """
            CREATE TABLE IF NOT EXISTS $TABLE_STORYBOARDS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_PROJECT_ID INTEGER NOT NULL,
                $COL_SHOT_NUMBER INTEGER NOT NULL,
                $COL_SCENE TEXT NOT NULL,
                $COL_ACTION TEXT NOT NULL,
                $COL_DIALOGUE TEXT NOT NULL,
                $COL_CAMERA TEXT NOT NULL,
                $COL_IMAGE_PROMPT TEXT NOT NULL,
                $COL_VIDEO_PROMPT TEXT NOT NULL,
                $COL_DURATION_SECONDS INTEGER NOT NULL,
                $COL_CHARACTER_NAMES TEXT,
                $COL_CHARACTER_IDS TEXT,
                $COL_IMAGE_STATUS TEXT NOT NULL DEFAULT 'PENDING',
                $COL_IMAGE_URL TEXT,
                $COL_IMAGE_LOCAL_PATH TEXT,
                $COL_IMAGE_ERROR_MESSAGE TEXT,
                $COL_VIDEO_STATUS TEXT NOT NULL DEFAULT 'PENDING',
                $COL_VIDEO_TASK_ID TEXT,
                $COL_VIDEO_URL TEXT,
                $COL_VIDEO_LOCAL_PATH TEXT,
                $COL_VIDEO_ERROR_MESSAGE TEXT,
                $COL_CREATED_AT INTEGER NOT NULL,
                $COL_UPDATED_AT INTEGER NOT NULL
            )
        """

        private const val SQL_CREATE_EPISODES = """
            CREATE TABLE IF NOT EXISTS $TABLE_EPISODES (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_PROJECT_ID INTEGER NOT NULL,
                $COL_EPISODE_NUMBER INTEGER NOT NULL DEFAULT 1,
                $COL_EPISODE_TITLE TEXT NOT NULL DEFAULT '',
                $COL_EPISODE_CONTENT TEXT,
                $COL_EPISODE_SCRIPT_CONTENT TEXT,
                $COL_EPISODE_STATUS TEXT NOT NULL DEFAULT 'DRAFT',
                $COL_CREATED_AT INTEGER NOT NULL,
                $COL_UPDATED_AT INTEGER NOT NULL
            )
        """

        private const val SQL_CREATE_CHARACTERS = """
            CREATE TABLE IF NOT EXISTS $TABLE_CHARACTERS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_CHARACTER_PROJECT_ID INTEGER NOT NULL,
                $COL_CHARACTER_EPISODE_ID INTEGER,
                $COL_CHARACTER_NAME TEXT NOT NULL,
                $COL_CHARACTER_ROLE TEXT NOT NULL DEFAULT '',
                $COL_CHARACTER_DESCRIPTION TEXT NOT NULL DEFAULT '',
                $COL_CHARACTER_APPEARANCE TEXT NOT NULL DEFAULT '',
                $COL_CHARACTER_PERSONALITY TEXT NOT NULL DEFAULT '',
                $COL_CHARACTER_IMAGE_STATUS TEXT NOT NULL DEFAULT 'PENDING',
                $COL_CHARACTER_IMAGE_URL TEXT,
                $COL_CHARACTER_IMAGE_LOCAL_PATH TEXT,
                $COL_CHARACTER_IMAGE_ERROR_MESSAGE TEXT,
                $COL_CREATED_AT INTEGER NOT NULL,
                $COL_UPDATED_AT INTEGER NOT NULL
            )
        """

        private const val SQL_CREATE_INDEX_CHARACTERS_PROJECT_ID = """
            CREATE INDEX IF NOT EXISTS idx_characters_project_id ON $TABLE_CHARACTERS($COL_CHARACTER_PROJECT_ID)
        """
    }
}
