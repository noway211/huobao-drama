import Foundation
import GRDB

public final class ProjectLocalDataSource {
    private let db: DatabaseQueue

    public init(db: DatabaseQueue) {
        self.db = db
    }

    func insertProject(_ project: DramaProject) throws -> Int64 {
        let now = LocalClock.nowMillis()
        let createdAt = project.createdAt > 0 ? project.createdAt : now
        let updatedAt = project.updatedAt > 0 ? project.updatedAt : now
        return try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO projects (
                        title, prompt, style, target_audience, aspect_ratio,
                        shot_count, shot_duration_seconds, status, current_stage,
                        error_message, generated_script, final_video_status,
                        final_video_local_path, final_video_error_message,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    project.title,
                    project.prompt,
                    project.style,
                    project.targetAudience,
                    project.aspectRatio,
                    project.shotCount,
                    project.shotDurationSeconds,
                    project.status.rawValue,
                    project.currentStage.rawValue,
                    project.errorMessage,
                    project.generatedScript,
                    project.finalVideoStatus.rawValue,
                    project.finalVideoLocalPath,
                    project.finalVideoErrorMessage,
                    createdAt,
                    updatedAt
                ]
            )
            return db.lastInsertedRowID
        }
    }

    func getProjects() throws -> [DramaProject] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM projects ORDER BY updated_at DESC")
                .map(Self.readProject)
        }
    }

    func getProject(_ id: Int64) throws -> DramaProject? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM projects WHERE id = ?", arguments: [id])
                .map(Self.readProject)
        }
    }

    func updateProjectTextResult(
        projectId: Int64,
        status: ProjectStatus,
        currentStage: GenerationStage,
        generatedScript: String?,
        errorMessage: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE projects
                    SET status = ?, current_stage = ?, generated_script = ?, error_message = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    status.rawValue,
                    currentStage.rawValue,
                    generatedScript,
                    errorMessage,
                    LocalClock.nowMillis(),
                    projectId
                ]
            )
        }
    }

    func updateProjectFinalVideo(
        projectId: Int64,
        status: ProjectStatus,
        currentStage: GenerationStage,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?,
        errorMessage: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE projects
                    SET status = ?, current_stage = ?, final_video_status = ?,
                        final_video_local_path = ?, final_video_error_message = ?,
                        error_message = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    status.rawValue,
                    currentStage.rawValue,
                    finalVideoStatus.rawValue,
                    finalVideoLocalPath,
                    finalVideoErrorMessage,
                    errorMessage,
                    LocalClock.nowMillis(),
                    projectId
                ]
            )
        }
    }

    func failProcessingProjects(message: String) throws -> Int {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE projects
                    SET status = ?, error_message = ?, updated_at = ?
                    WHERE status = ?
                    """,
                arguments: [
                    ProjectStatus.failed.rawValue,
                    message,
                    LocalClock.nowMillis(),
                    ProjectStatus.processing.rawValue
                ]
            )
            return db.changesCount
        }
    }

    func deleteProject(_ projectId: Int64) throws -> Bool {
        try db.write { db in
            try db.execute(sql: "DELETE FROM projects WHERE id = ?", arguments: [projectId])
            return db.changesCount > 0
        }
    }

    private static func readProject(_ row: Row) -> DramaProject {
        DramaProject(
            id: row["id"],
            title: row["title"],
            prompt: row["prompt"],
            style: row["style"],
            targetAudience: row["target_audience"],
            aspectRatio: row["aspect_ratio"],
            shotCount: row["shot_count"],
            shotDurationSeconds: row["shot_duration_seconds"],
            status: ProjectStatus(persisted: row["status"]),
            currentStage: GenerationStage(persisted: row["current_stage"]),
            errorMessage: row["error_message"],
            generatedScript: row["generated_script"],
            finalVideoStatus: AssetStatus(persisted: row["final_video_status"]),
            finalVideoLocalPath: row["final_video_local_path"],
            finalVideoErrorMessage: row["final_video_error_message"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
