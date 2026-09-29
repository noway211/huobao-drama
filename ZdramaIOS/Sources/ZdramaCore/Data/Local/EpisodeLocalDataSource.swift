import Foundation
import GRDB

public final class EpisodeLocalDataSource {
    private let db: DatabaseQueue

    public init(db: DatabaseQueue) {
        self.db = db
    }

    func insertEpisode(_ episode: Episode) throws -> Int64 {
        let now = LocalClock.nowMillis()
        let createdAt = episode.createdAt > 0 ? episode.createdAt : now
        let updatedAt = episode.updatedAt > 0 ? episode.updatedAt : now
        return try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO episodes (
                        project_id, episode_number, episode_title, content, script_content,
                        episode_status, final_video_status, final_video_local_path,
                        final_video_error_message, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    episode.projectId,
                    episode.episodeNumber,
                    episode.title,
                    episode.content,
                    episode.scriptContent,
                    episode.status.rawValue,
                    episode.finalVideoStatus.rawValue,
                    episode.finalVideoLocalPath,
                    episode.finalVideoErrorMessage,
                    createdAt,
                    updatedAt
                ]
            )
            return db.lastInsertedRowID
        }
    }

    func getEpisodeById(_ id: Int64) throws -> Episode? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM episodes WHERE id = ?", arguments: [id])
                .map(Self.readEpisode)
        }
    }

    func getEpisodeForProject(_ projectId: Int64) throws -> Episode? {
        try db.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM episodes
                    WHERE project_id = ?
                    ORDER BY episode_number ASC
                    LIMIT 1
                    """,
                arguments: [projectId]
            ).map(Self.readEpisode)
        }
    }

    func getEpisodes(_ projectId: Int64) throws -> [Episode] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM episodes
                    WHERE project_id = ?
                    ORDER BY episode_number ASC
                    """,
                arguments: [projectId]
            ).map(Self.readEpisode)
        }
    }

    func updateEpisodeScriptContent(
        episodeId: Int64,
        scriptContent: String?,
        status: EpisodeStatus
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE episodes
                    SET script_content = ?, episode_status = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [scriptContent, status.rawValue, LocalClock.nowMillis(), episodeId]
            )
        }
    }

    func updateEpisodeFinalVideo(
        episodeId: Int64,
        finalVideoStatus: AssetStatus,
        finalVideoLocalPath: String?,
        finalVideoErrorMessage: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE episodes
                    SET final_video_status = ?, final_video_local_path = ?,
                        final_video_error_message = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    finalVideoStatus.rawValue,
                    finalVideoLocalPath,
                    finalVideoErrorMessage,
                    LocalClock.nowMillis(),
                    episodeId
                ]
            )
        }
    }

    func deleteEpisodesForProject(_ projectId: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM episodes WHERE project_id = ?", arguments: [projectId])
        }
    }

    private static func readEpisode(_ row: Row) -> Episode {
        Episode(
            id: row["id"],
            projectId: row["project_id"],
            episodeNumber: row["episode_number"],
            title: row["episode_title"] ?? "",
            content: row["content"],
            scriptContent: row["script_content"],
            status: EpisodeStatus(persisted: row["episode_status"]),
            finalVideoStatus: AssetStatus(persisted: row["final_video_status"]),
            finalVideoLocalPath: row["final_video_local_path"],
            finalVideoErrorMessage: row["final_video_error_message"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
