import Foundation
import GRDB

public enum DramaDatabase {
    public static let schemaVersion = 12

    public static func open(at url: URL) throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(path: url.path)
        try installSchema(on: dbQueue)
        return dbQueue
    }

    public static func openInMemory() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try installSchema(on: dbQueue)
        return dbQueue
    }

    private static func installSchema(on dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try db.execute(sql: sqlCreateProjects)
            try db.execute(sql: sqlCreateStoryboards)
            try db.execute(sql: sqlCreateEpisodes)
            try db.execute(sql: sqlCreateCharacters)
            try db.execute(sql: sqlCreateIndexCharactersProjectId)
            try db.execute(sql: "PRAGMA user_version = \(schemaVersion)")
        }
    }

    // Copied from Android DramaLocalDatabase companion SQL (v12).
    static let sqlCreateProjects = """
        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            prompt TEXT NOT NULL,
            style TEXT NOT NULL,
            target_audience TEXT NOT NULL,
            aspect_ratio TEXT NOT NULL,
            shot_count INTEGER NOT NULL,
            shot_duration_seconds INTEGER NOT NULL,
            status TEXT NOT NULL,
            current_stage TEXT NOT NULL,
            error_message TEXT,
            generated_script TEXT,
            final_video_status TEXT NOT NULL DEFAULT 'PENDING',
            final_video_local_path TEXT,
            final_video_error_message TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """

    static let sqlCreateStoryboards = """
        CREATE TABLE IF NOT EXISTS storyboards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL,
            episode_id INTEGER,
            shot_number INTEGER NOT NULL,
            scene TEXT NOT NULL,
            action TEXT NOT NULL,
            dialogue TEXT NOT NULL,
            camera TEXT NOT NULL,
            image_prompt TEXT NOT NULL,
            video_prompt TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            character_names TEXT,
            character_ids TEXT,
            image_status TEXT NOT NULL DEFAULT 'PENDING',
            image_url TEXT,
            image_local_path TEXT,
            image_error_message TEXT,
            video_status TEXT NOT NULL DEFAULT 'PENDING',
            video_task_id TEXT,
            video_url TEXT,
            video_local_path TEXT,
            video_error_message TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """

    static let sqlCreateEpisodes = """
        CREATE TABLE IF NOT EXISTS episodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL,
            episode_number INTEGER NOT NULL DEFAULT 1,
            episode_title TEXT NOT NULL DEFAULT '',
            content TEXT,
            script_content TEXT,
            episode_status TEXT NOT NULL DEFAULT 'DRAFT',
            final_video_status TEXT NOT NULL DEFAULT 'PENDING',
            final_video_local_path TEXT,
            final_video_error_message TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """

    static let sqlCreateCharacters = """
        CREATE TABLE IF NOT EXISTS characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL,
            episode_id INTEGER,
            name TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            appearance TEXT NOT NULL DEFAULT '',
            personality TEXT NOT NULL DEFAULT '',
            image_status TEXT NOT NULL DEFAULT 'PENDING',
            image_url TEXT,
            image_local_path TEXT,
            image_error_message TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """

    static let sqlCreateIndexCharactersProjectId = """
        CREATE INDEX IF NOT EXISTS idx_characters_project_id ON characters(project_id)
        """
}

enum LocalClock {
    static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
