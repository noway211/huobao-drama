#import "ZDDramaRepository.h"
#import "ZDDramaDatabase.h"
#import "ZDGeneratedMediaPaths.h"
#import <sqlite3.h>

@interface ZDDramaRepository ()
@property (nonatomic) sqlite3 *db;
@property (nonatomic, copy) NSString *filesRoot;
@end

@implementation ZDDramaRepository

+ (instancetype)repositoryWithDatabasePath:(NSString *)path filesRoot:(NSString *)filesRoot {
    ZDDramaRepository *repo = [ZDDramaRepository new];
    repo.filesRoot = filesRoot ?: @"";
    repo.db = ZDDramaDatabaseOpenAtPath(path, nil);
    return repo;
}

- (void)dealloc {
    if (_db) sqlite3_close(_db);
}

static int64_t ZDNow(void) {
    return (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static void ZDBindText(sqlite3_stmt *stmt, int index, NSString *value) {
    if (value == nil) {
        sqlite3_bind_null(stmt, index);
    } else {
        sqlite3_bind_text(stmt, index, value.UTF8String, -1, SQLITE_TRANSIENT);
    }
}

- (int64_t)createProjectFromInput:(ZDCreateDramaInput *)input {
    int64_t now = ZDNow();
    sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL);
    const char *sql =
        "INSERT INTO projects (title, prompt, style, target_audience, aspect_ratio, shot_count, shot_duration_seconds, status, current_stage, final_video_status, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, 'DRAFT', 'NONE', 'PENDING', ?, ?)";
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    ZDBindText(stmt, 1, input.title ?: @"");
    ZDBindText(stmt, 2, input.prompt ?: @"");
    ZDBindText(stmt, 3, input.style ?: @"");
    ZDBindText(stmt, 4, input.targetAudience ?: @"");
    ZDBindText(stmt, 5, input.aspectRatio ?: @"");
    sqlite3_bind_int(stmt, 6, (int)input.shotCount);
    sqlite3_bind_int(stmt, 7, (int)input.shotDurationSeconds);
    sqlite3_bind_int64(stmt, 8, now);
    sqlite3_bind_int64(stmt, 9, now);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    int64_t projectId = sqlite3_last_insert_rowid(self.db);
    [self createEpisodeForProjectId:projectId title:input.title content:input.prompt];
    sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL);
    return projectId;
}

- (ZDDramaProject *)projectFromStatement:(sqlite3_stmt *)stmt {
    ZDDramaProject *project = [ZDDramaProject new];
    project.id = sqlite3_column_int64(stmt, 0);
    project.title = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)] ?: @"";
    project.prompt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)] ?: @"";
    project.style = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 3)] ?: @"";
    project.targetAudience = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 4)] ?: @"";
    project.aspectRatio = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)] ?: @"";
    project.shotCount = sqlite3_column_int(stmt, 6);
    project.shotDurationSeconds = sqlite3_column_int(stmt, 7);
    project.status = ZDProjectStatusFromPersisted([NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 8)]);
    project.currentStage = ZDGenerationStageFromPersisted([NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 9)]);
    project.updatedAt = sqlite3_column_int64(stmt, 10);
    return project;
}

- (NSArray<ZDDramaProject *> *)getProjects {
    const char *sql = "SELECT id, title, prompt, style, target_audience, aspect_ratio, shot_count, shot_duration_seconds, status, current_stage, updated_at FROM projects ORDER BY updated_at DESC";
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    NSMutableArray *projects = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        [projects addObject:[self projectFromStatement:stmt]];
    }
    sqlite3_finalize(stmt);
    return projects;
}

- (ZDDramaProject *)getProject:(int64_t)projectId {
    const char *sql = "SELECT id, title, prompt, style, target_audience, aspect_ratio, shot_count, shot_duration_seconds, status, current_stage, updated_at FROM projects WHERE id = ?";
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    sqlite3_bind_int64(stmt, 1, projectId);
    ZDDramaProject *project = sqlite3_step(stmt) == SQLITE_ROW ? [self projectFromStatement:stmt] : nil;
    sqlite3_finalize(stmt);
    return project;
}

- (int64_t)createEpisodeForProjectId:(int64_t)projectId title:(NSString *)title content:(NSString *)content {
    int64_t now = ZDNow();
    const char *sql =
        "INSERT INTO episodes (project_id, episode_number, episode_title, content, episode_status, final_video_status, created_at, updated_at) "
        "VALUES (?, 1, ?, ?, 'DRAFT', 'PENDING', ?, ?)";
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    sqlite3_bind_int64(stmt, 1, projectId);
    ZDBindText(stmt, 2, title ?: @"");
    ZDBindText(stmt, 3, content);
    sqlite3_bind_int64(stmt, 4, now);
    sqlite3_bind_int64(stmt, 5, now);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return sqlite3_last_insert_rowid(self.db);
}

- (ZDEpisode *)getEpisodeForProject:(int64_t)projectId {
    const char *sql = "SELECT id, project_id, episode_number, episode_title, content, script_content, episode_status FROM episodes WHERE project_id = ? ORDER BY episode_number ASC LIMIT 1";
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);
    sqlite3_bind_int64(stmt, 1, projectId);
    ZDEpisode *episode = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        episode = [ZDEpisode new];
        episode.id = sqlite3_column_int64(stmt, 0);
        episode.projectId = sqlite3_column_int64(stmt, 1);
        episode.episodeNumber = sqlite3_column_int(stmt, 2);
        const char *title = (const char *)sqlite3_column_text(stmt, 3);
        episode.title = title ? [NSString stringWithUTF8String:title] : @"";
        const char *content = (const char *)sqlite3_column_text(stmt, 4);
        episode.content = content ? [NSString stringWithUTF8String:content] : nil;
        const char *script = (const char *)sqlite3_column_text(stmt, 5);
        episode.scriptContent = script ? [NSString stringWithUTF8String:script] : nil;
        const char *status = (const char *)sqlite3_column_text(stmt, 6);
        episode.status = ZDEpisodeStatusFromPersisted(status ? [NSString stringWithUTF8String:status] : nil);
    }
    sqlite3_finalize(stmt);
    return episode;
}

- (BOOL)replaceStoryboards:(NSArray<ZDStoryboardShot *> *)shots forEpisodeId:(int64_t)episodeId {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "DELETE FROM storyboards WHERE episode_id = ?", -1, &stmt, NULL);
    sqlite3_bind_int64(stmt, 1, episodeId);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return YES;
}

- (BOOL)deleteProject:(int64_t)projectId {
    const char *sqls[] = {
        "DELETE FROM storyboards WHERE project_id = ?",
        "DELETE FROM episodes WHERE project_id = ?",
        "DELETE FROM characters WHERE project_id = ?",
        "DELETE FROM projects WHERE id = ?"
    };
    for (int i = 0; i < 4; i++) {
        sqlite3_stmt *stmt = NULL;
        sqlite3_prepare_v2(self.db, sqls[i], -1, &stmt, NULL);
        sqlite3_bind_int64(stmt, 1, projectId);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
    ZDGeneratedMediaPaths *paths = [[ZDGeneratedMediaPaths alloc] initWithRoot:self.filesRoot];
    NSURL *dir = [paths projectDir:projectId];
    if ([NSFileManager.defaultManager fileExistsAtPath:dir.path]) {
        [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    }
    return [self getProject:projectId] == nil;
}

@end
