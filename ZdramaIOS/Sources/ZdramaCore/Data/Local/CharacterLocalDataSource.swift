import Foundation
import GRDB

public final class CharacterLocalDataSource {
    private let db: DatabaseQueue

    public init(db: DatabaseQueue) {
        self.db = db
    }

    func deleteCharactersForProject(_ projectId: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM characters WHERE project_id = ?", arguments: [projectId])
        }
    }
}
