#import "ZDDramaDatabase.h"

static NSString *const ZDDatabaseDomain = @"ZDDramaDatabase";

static BOOL ZDExec(sqlite3 *db, const char *sql, NSError **error) {
    char *message = NULL;
    if (sqlite3_exec(db, sql, NULL, NULL, &message) == SQLITE_OK) {
        return YES;
    }
    if (error) {
        NSString *text = message ? [NSString stringWithUTF8String:message] : @"sqlite error";
        *error = [NSError errorWithDomain:ZDDatabaseDomain code:1 userInfo:@{NSLocalizedDescriptionKey: text}];
    }
    sqlite3_free(message);
    return NO;
}

sqlite3 *ZDDramaDatabaseOpenAtPath(NSString *path, NSError **error) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:ZDDatabaseDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"无法打开数据库"}];
        }
        sqlite3_close(db);
        return NULL;
    }
    const char *schema =
        "CREATE TABLE IF NOT EXISTS projects ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "title TEXT NOT NULL,"
        "prompt TEXT NOT NULL,"
        "style TEXT NOT NULL,"
        "target_audience TEXT NOT NULL,"
        "aspect_ratio TEXT NOT NULL,"
        "shot_count INTEGER NOT NULL,"
        "shot_duration_seconds INTEGER NOT NULL,"
        "status TEXT NOT NULL,"
        "current_stage TEXT NOT NULL,"
        "error_message TEXT,"
        "generated_script TEXT,"
        "final_video_status TEXT NOT NULL DEFAULT 'PENDING',"
        "final_video_local_path TEXT,"
        "final_video_error_message TEXT,"
        "created_at INTEGER NOT NULL,"
        "updated_at INTEGER NOT NULL);"
        "CREATE TABLE IF NOT EXISTS storyboards ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "project_id INTEGER NOT NULL,"
        "episode_id INTEGER,"
        "shot_number INTEGER NOT NULL,"
        "scene TEXT NOT NULL,"
        "action TEXT NOT NULL,"
        "dialogue TEXT NOT NULL,"
        "camera TEXT NOT NULL,"
        "image_prompt TEXT NOT NULL,"
        "video_prompt TEXT NOT NULL,"
        "duration_seconds INTEGER NOT NULL,"
        "character_names TEXT,"
        "character_ids TEXT,"
        "image_status TEXT NOT NULL DEFAULT 'PENDING',"
        "image_url TEXT,"
        "image_local_path TEXT,"
        "image_error_message TEXT,"
        "video_status TEXT NOT NULL DEFAULT 'PENDING',"
        "video_task_id TEXT,"
        "video_url TEXT,"
        "video_local_path TEXT,"
        "video_error_message TEXT,"
        "created_at INTEGER NOT NULL,"
        "updated_at INTEGER NOT NULL);"
        "CREATE TABLE IF NOT EXISTS episodes ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "project_id INTEGER NOT NULL,"
        "episode_number INTEGER NOT NULL DEFAULT 1,"
        "episode_title TEXT NOT NULL DEFAULT '',"
        "content TEXT,"
        "script_content TEXT,"
        "episode_status TEXT NOT NULL DEFAULT 'DRAFT',"
        "final_video_status TEXT NOT NULL DEFAULT 'PENDING',"
        "final_video_local_path TEXT,"
        "final_video_error_message TEXT,"
        "created_at INTEGER NOT NULL,"
        "updated_at INTEGER NOT NULL);"
        "CREATE TABLE IF NOT EXISTS characters ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "project_id INTEGER NOT NULL,"
        "episode_id INTEGER,"
        "name TEXT NOT NULL,"
        "role TEXT NOT NULL DEFAULT '',"
        "description TEXT NOT NULL DEFAULT '',"
        "appearance TEXT NOT NULL DEFAULT '',"
        "personality TEXT NOT NULL DEFAULT '',"
        "image_status TEXT NOT NULL DEFAULT 'PENDING',"
        "image_url TEXT,"
        "image_local_path TEXT,"
        "image_error_message TEXT,"
        "created_at INTEGER NOT NULL,"
        "updated_at INTEGER NOT NULL);"
        "CREATE INDEX IF NOT EXISTS idx_characters_project_id ON characters(project_id);"
        "PRAGMA user_version = 12;";
    if (!ZDExec(db, schema, error)) {
        sqlite3_close(db);
        return NULL;
    }
    return db;
}
