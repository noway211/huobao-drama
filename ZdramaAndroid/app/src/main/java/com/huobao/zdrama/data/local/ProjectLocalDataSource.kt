package com.huobao.zdrama.data.local

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.DramaProject
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus

class ProjectLocalDataSource(context: Context) {
    private val database = DramaLocalDatabase(context)

    fun insertProject(project: DramaProject): Long {
        val now = if (project.createdAt > 0L) project.createdAt else System.currentTimeMillis()
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_TITLE, project.title)
            put(DramaLocalDatabase.COL_PROMPT, project.prompt)
            put(DramaLocalDatabase.COL_STYLE, project.style)
            put(DramaLocalDatabase.COL_TARGET_AUDIENCE, project.targetAudience)
            put(DramaLocalDatabase.COL_ASPECT_RATIO, project.aspectRatio)
            put(DramaLocalDatabase.COL_SHOT_COUNT, project.shotCount)
            put(DramaLocalDatabase.COL_SHOT_DURATION_SECONDS, project.shotDurationSeconds)
            put(DramaLocalDatabase.COL_STATUS, project.status.name)
            put(DramaLocalDatabase.COL_CURRENT_STAGE, project.currentStage.name)
            put(DramaLocalDatabase.COL_ERROR_MESSAGE, project.errorMessage)
            put(DramaLocalDatabase.COL_GENERATED_SCRIPT, project.generatedScript)
            put(DramaLocalDatabase.COL_FINAL_VIDEO_STATUS, project.finalVideoStatus.name)
            put(DramaLocalDatabase.COL_FINAL_VIDEO_LOCAL_PATH, project.finalVideoLocalPath)
            put(DramaLocalDatabase.COL_FINAL_VIDEO_ERROR_MESSAGE, project.finalVideoErrorMessage)
            put(DramaLocalDatabase.COL_CREATED_AT, now)
            put(DramaLocalDatabase.COL_UPDATED_AT, now)
        }
        return database.writableDatabase.insert(DramaLocalDatabase.TABLE_PROJECTS, null, values)
    }

    fun getProjects(): List<DramaProject> {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_PROJECTS,
            null,
            null,
            null,
            null,
            null,
            "${DramaLocalDatabase.COL_UPDATED_AT} DESC"
        )
        return cursor.use { readProjects(it) }
    }

    fun deleteProject(projectId: Long): Int {
        return database.writableDatabase.delete(
            DramaLocalDatabase.TABLE_PROJECTS,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    fun getProject(projectId: Long): DramaProject? {
        val cursor = database.readableDatabase.query(
            DramaLocalDatabase.TABLE_PROJECTS,
            null,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(projectId.toString()),
            null,
            null,
            null,
            "1"
        )
        return cursor.use {
            if (it.moveToFirst()) readProject(it) else null
        }
    }

    fun updateProjectTextResult(
        projectId: Long,
        status: ProjectStatus,
        currentStage: GenerationStage,
        generatedScript: String?,
        errorMessage: String?
    ): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_STATUS, status.name)
            put(DramaLocalDatabase.COL_CURRENT_STAGE, currentStage.name)
            put(DramaLocalDatabase.COL_GENERATED_SCRIPT, generatedScript)
            put(DramaLocalDatabase.COL_ERROR_MESSAGE, errorMessage)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_PROJECTS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    fun updateProjectFinalVideo(
        projectId: Long,
        status: ProjectStatus,
        currentStage: GenerationStage,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?,
        errorMessage: String?
    ): Int {
        val values = ContentValues().apply {
            put(DramaLocalDatabase.COL_STATUS, status.name)
            put(DramaLocalDatabase.COL_CURRENT_STAGE, currentStage.name)
            put(DramaLocalDatabase.COL_FINAL_VIDEO_STATUS, finalVideoStatus.name)
            put(DramaLocalDatabase.COL_FINAL_VIDEO_LOCAL_PATH, finalVideoLocalPath)
            put(DramaLocalDatabase.COL_FINAL_VIDEO_ERROR_MESSAGE, finalVideoErrorMessage)
            put(DramaLocalDatabase.COL_ERROR_MESSAGE, errorMessage)
            put(DramaLocalDatabase.COL_UPDATED_AT, System.currentTimeMillis())
        }
        return database.writableDatabase.update(
            DramaLocalDatabase.TABLE_PROJECTS,
            values,
            "${DramaLocalDatabase.COL_ID} = ?",
            arrayOf(projectId.toString())
        )
    }

    private fun readProjects(cursor: Cursor): List<DramaProject> {
        val projects = mutableListOf<DramaProject>()
        while (cursor.moveToNext()) {
            projects.add(readProject(cursor))
        }
        return projects
    }

    private fun readProject(cursor: Cursor): DramaProject {
        return DramaProject(
            id = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ID)),
            title = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_TITLE)),
            prompt = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_PROMPT)),
            style = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_STYLE)),
            targetAudience = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_TARGET_AUDIENCE)),
            aspectRatio = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ASPECT_RATIO)),
            shotCount = cursor.getInt(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SHOT_COUNT)),
            shotDurationSeconds = cursor.getInt(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_SHOT_DURATION_SECONDS)),
            status = parseProjectStatus(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_STATUS))),
            currentStage = parseGenerationStage(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CURRENT_STAGE))),
            errorMessage = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_ERROR_MESSAGE)),
            generatedScript = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_GENERATED_SCRIPT)),
            finalVideoStatus = parseAssetStatus(cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_FINAL_VIDEO_STATUS))),
            finalVideoLocalPath = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_FINAL_VIDEO_LOCAL_PATH)),
            finalVideoErrorMessage = cursor.getString(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_FINAL_VIDEO_ERROR_MESSAGE)),
            createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_CREATED_AT)),
            updatedAt = cursor.getLong(cursor.getColumnIndexOrThrow(DramaLocalDatabase.COL_UPDATED_AT))
        )
    }

    private fun parseProjectStatus(value: String): ProjectStatus {
        return runCatching { ProjectStatus.valueOf(value) }.getOrDefault(ProjectStatus.DRAFT)
    }

    private fun parseGenerationStage(value: String): GenerationStage {
        return runCatching { GenerationStage.valueOf(value) }.getOrDefault(GenerationStage.NONE)
    }

    private fun parseAssetStatus(value: String?): AssetStatus {
        return runCatching { AssetStatus.valueOf(value ?: AssetStatus.PENDING.name) }
            .getOrDefault(AssetStatus.PENDING)
    }
}
