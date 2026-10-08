import Foundation
import GRDB

public final class StoryboardLocalDataSource {
    private let db: DatabaseQueue

    public init(db: DatabaseQueue) {
        self.db = db
    }

    func replaceStoryboards(projectId: Int64, episodeId: Int64, shots: [StoryboardShot]) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM storyboards WHERE project_id = ? AND episode_id = ?",
                arguments: [projectId, episodeId]
            )
            for shot in shots {
                try insertStoryboard(db, shot, projectId: projectId, episodeId: episodeId)
            }
        }
    }

    func getStoryboards(projectId: Int64, episodeId: Int64) throws -> [StoryboardShot] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM storyboards
                    WHERE project_id = ? AND episode_id = ?
                    ORDER BY shot_number ASC
                    """,
                arguments: [projectId, episodeId]
            ).map(Self.readShot)
        }
    }

    func updateShotImage(
        shotId: Int64,
        imageStatus: AssetStatus,
        imageUrl: String?,
        imageLocalPath: String?,
        imageErrorMessage: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE storyboards
                    SET image_status = ?, image_url = ?, image_local_path = ?,
                        image_error_message = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    imageStatus.rawValue,
                    imageUrl,
                    imageLocalPath,
                    imageErrorMessage,
                    LocalClock.nowMillis(),
                    shotId
                ]
            )
        }
    }

    func updateShotVideo(
        shotId: Int64,
        videoStatus: AssetStatus,
        videoTaskId: String?,
        videoUrl: String?,
        videoLocalPath: String?,
        videoErrorMessage: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE storyboards
                    SET video_status = ?, video_task_id = ?, video_url = ?,
                        video_local_path = ?, video_error_message = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    videoStatus.rawValue,
                    videoTaskId,
                    videoUrl,
                    videoLocalPath,
                    videoErrorMessage,
                    LocalClock.nowMillis(),
                    shotId
                ]
            )
        }
    }

    func updateShotImagePrompt(shotId: Int64, newPrompt: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE storyboards
                    SET image_prompt = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [newPrompt, LocalClock.nowMillis(), shotId]
            )
            guard db.changesCount > 0 else {
                throw LocalizedMessageError("镜头不存在或已被替换")
            }
        }
    }

    func updateShotVideoPrompt(shotId: Int64, newPrompt: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE storyboards
                    SET video_prompt = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [newPrompt, LocalClock.nowMillis(), shotId]
            )
            guard db.changesCount > 0 else {
                throw LocalizedMessageError("镜头不存在或已被替换")
            }
        }
    }

    func deleteStoryboards(projectId: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM storyboards WHERE project_id = ?", arguments: [projectId])
        }
    }

    private func insertStoryboard(
        _ db: Database,
        _ shot: StoryboardShot,
        projectId: Int64,
        episodeId: Int64
    ) throws {
        let now = LocalClock.nowMillis()
        let createdAt = shot.createdAt > 0 ? shot.createdAt : now
        let updatedAt = shot.updatedAt > 0 ? shot.updatedAt : now
        try db.execute(
            sql: """
                INSERT INTO storyboards (
                    project_id, episode_id, shot_number, scene, action, dialogue, camera,
                    image_prompt, video_prompt, duration_seconds, character_names, character_ids,
                    image_status, image_url, image_local_path, image_error_message,
                    video_status, video_task_id, video_url, video_local_path, video_error_message,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                projectId,
                episodeId,
                shot.shotNumber,
                shot.scene,
                shot.action,
                shot.dialogue,
                shot.camera,
                shot.imagePrompt,
                shot.videoPrompt,
                shot.durationSeconds,
                Self.encodeCharacterNames(shot.characterNames),
                shot.characterIds,
                shot.imageStatus.rawValue,
                shot.imageUrl,
                shot.imageLocalPath,
                shot.imageErrorMessage,
                shot.videoStatus.rawValue,
                shot.videoTaskId,
                shot.videoUrl,
                shot.videoLocalPath,
                shot.videoErrorMessage,
                createdAt,
                updatedAt
            ]
        )
    }

    private static func readShot(_ row: Row) -> StoryboardShot {
        StoryboardShot(
            id: row["id"],
            projectId: row["project_id"],
            episodeId: row["episode_id"],
            shotNumber: row["shot_number"],
            scene: row["scene"],
            action: row["action"],
            dialogue: row["dialogue"],
            camera: row["camera"],
            imagePrompt: row["image_prompt"],
            videoPrompt: row["video_prompt"],
            durationSeconds: row["duration_seconds"],
            characterNames: decodeCharacterNames(row["character_names"]),
            characterIds: row["character_ids"],
            imageStatus: AssetStatus(persisted: row["image_status"]),
            imageUrl: row["image_url"],
            imageLocalPath: row["image_local_path"],
            imageErrorMessage: row["image_error_message"],
            videoStatus: AssetStatus(persisted: row["video_status"]),
            videoTaskId: row["video_task_id"],
            videoUrl: row["video_url"],
            videoLocalPath: row["video_local_path"],
            videoErrorMessage: row["video_error_message"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func encodeCharacterNames(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(names) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeCharacterNames(_ json: String?) -> [String] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
