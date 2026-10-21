import Foundation
import GRDB

public final class CharacterLocalDataSource {
    private let db: DatabaseQueue

    public init(db: DatabaseQueue) {
        self.db = db
    }

    func getCharacters(projectId: Int64) throws -> [Character] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM characters WHERE project_id = ? ORDER BY id ASC",
                arguments: [projectId]
            ).map(Self.readCharacter)
        }
    }

    func upsertCharacters(projectId: Int64, characters: [Character]) throws {
        let now = LocalClock.nowMillis()
        try db.write { db in
            for character in characters {
                if character.id > 0 {
                    try db.execute(
                        sql: """
                            UPDATE characters
                            SET role = ?, description = ?, appearance = ?, personality = ?, updated_at = ?
                            WHERE id = ? AND project_id = ?
                            """,
                        arguments: [
                            character.role,
                            character.description,
                            character.appearance,
                            character.personality,
                            now,
                            character.id,
                            projectId
                        ]
                    )
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO characters (
                                project_id, episode_id, name, role, description, appearance, personality,
                                image_status, image_url, image_local_path, image_error_message,
                                created_at, updated_at
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            projectId,
                            character.episodeId,
                            character.name,
                            character.role,
                            character.description,
                            character.appearance,
                            character.personality,
                            character.imageStatus.rawValue,
                            character.imageUrl,
                            character.imageLocalPath,
                            character.imageErrorMessage,
                            now,
                            now
                        ]
                    )
                }
            }
        }
    }

    func updateCharacterImage(
        characterId: Int64,
        status: AssetStatus,
        url: String?,
        localPath: String?,
        errorMessage: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE characters
                    SET image_status = ?, image_url = ?, image_local_path = ?,
                        image_error_message = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    status.rawValue,
                    url,
                    localPath,
                    errorMessage,
                    LocalClock.nowMillis(),
                    characterId
                ]
            )
        }
    }

    func deleteCharactersForProject(_ projectId: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM characters WHERE project_id = ?", arguments: [projectId])
        }
    }

    private static func readCharacter(_ row: Row) -> Character {
        Character(
            id: row["id"],
            projectId: row["project_id"],
            episodeId: row["episode_id"],
            name: row["name"],
            role: row["role"],
            description: row["description"],
            appearance: row["appearance"],
            personality: row["personality"],
            imageStatus: AssetStatus(persisted: row["image_status"]),
            imageUrl: row["image_url"],
            imageLocalPath: row["image_local_path"],
            imageErrorMessage: row["image_error_message"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
