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
    const char *script = (const char *)sqlite3_column_text(stmt, 10);
    project.generatedScript = script ? [NSString stringWithUTF8String:script] : nil;
    const char *errorMessage = (const char *)sqlite3_column_text(stmt, 11);
    project.errorMessage = errorMessage ? [NSString stringWithUTF8String:errorMessage] : nil;
    project.finalVideoStatus = ZDAssetStatusFromPersisted([NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 12)]);
    const char *finalError = (const char *)sqlite3_column_text(stmt, 13);
    project.finalVideoErrorMessage = finalError ? [NSString stringWithUTF8String:finalError] : nil;
    project.updatedAt = sqlite3_column_int64(stmt, 14);
    return project;
}

- (NSArray<ZDDramaProject *> *)getProjects {
    const char *sql = "SELECT id, title, prompt, style, target_audience, aspect_ratio, shot_count, shot_duration_seconds, status, current_stage, generated_script, error_message, final_video_status, final_video_error_message, updated_at FROM projects ORDER BY updated_at DESC";
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
    const char *sql = "SELECT id, title, prompt, style, target_audience, aspect_ratio, shot_count, shot_duration_seconds, status, current_stage, generated_script, error_message, final_video_status, final_video_error_message, updated_at FROM projects WHERE id = ?";
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

- (BOOL)updateEpisodeScriptContent:(NSString *)script episodeId:(int64_t)episodeId status:(NSString *)status {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE episodes SET script_content = ?, episode_status = ?, updated_at = ? WHERE id = ?", -1, &stmt, NULL);
    ZDBindText(stmt, 1, script);
    ZDBindText(stmt, 2, status ?: @"DRAFT");
    sqlite3_bind_int64(stmt, 3, ZDNow());
    sqlite3_bind_int64(stmt, 4, episodeId);
    BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

- (BOOL)updateProjectTextResult:(int64_t)projectId status:(NSString *)status stage:(NSString *)stage generatedScript:(NSString *)script errorMessage:(NSString *)errorMessage {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE projects SET status = ?, current_stage = ?, generated_script = ?, error_message = ?, updated_at = ? WHERE id = ?", -1, &stmt, NULL);
    ZDBindText(stmt, 1, status ?: @"DRAFT");
    ZDBindText(stmt, 2, stage ?: @"NONE");
    ZDBindText(stmt, 3, script);
    ZDBindText(stmt, 4, errorMessage);
    sqlite3_bind_int64(stmt, 5, ZDNow());
    sqlite3_bind_int64(stmt, 6, projectId);
    BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

- (ZDStoryboardShot *)shotFromStatement:(sqlite3_stmt *)stmt {
    ZDStoryboardShot *shot = [ZDStoryboardShot new];
    shot.id = sqlite3_column_int64(stmt, 0);
    shot.projectId = sqlite3_column_int64(stmt, 1);
    shot.episodeIdIsNull = sqlite3_column_type(stmt, 2) == SQLITE_NULL;
    shot.episodeId = shot.episodeIdIsNull ? 0 : sqlite3_column_int64(stmt, 2);
    shot.shotNumber = sqlite3_column_int(stmt, 3);
    const char *scene = (const char *)sqlite3_column_text(stmt, 4);
    shot.scene = scene ? [NSString stringWithUTF8String:scene] : @"";
    const char *imageStatus = (const char *)sqlite3_column_text(stmt, 5);
    shot.imageStatus = imageStatus ? [NSString stringWithUTF8String:imageStatus] : @"PENDING";
    const char *imagePath = (const char *)sqlite3_column_text(stmt, 6);
    shot.imageLocalPath = imagePath ? [NSString stringWithUTF8String:imagePath] : nil;
    const char *imageError = (const char *)sqlite3_column_text(stmt, 7);
    shot.imageErrorMessage = imageError ? [NSString stringWithUTF8String:imageError] : nil;
    const char *videoStatus = (const char *)sqlite3_column_text(stmt, 8);
    shot.videoStatus = videoStatus ? [NSString stringWithUTF8String:videoStatus] : @"PENDING";
    const char *videoPath = (const char *)sqlite3_column_text(stmt, 9);
    shot.videoLocalPath = videoPath ? [NSString stringWithUTF8String:videoPath] : nil;
    const char *imageUrl = (const char *)sqlite3_column_text(stmt, 10);
    shot.imageUrl = imageUrl ? [NSString stringWithUTF8String:imageUrl] : nil;
    return shot;
}

- (NSArray<ZDStoryboardShot *> *)getStoryboardsForEpisode:(int64_t)episodeId {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "SELECT id, project_id, episode_id, shot_number, scene, image_status, image_local_path, image_error_message, video_status, video_local_path, image_url FROM storyboards WHERE episode_id = ? ORDER BY shot_number ASC", -1, &stmt, NULL);
    sqlite3_bind_int64(stmt, 1, episodeId);
    NSMutableArray *shots = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) [shots addObject:[self shotFromStatement:stmt]];
    sqlite3_finalize(stmt);
    return shots;
}

- (BOOL)updateShotImageId:(int64_t)shotId status:(NSString *)status localPath:(NSString *)path url:(NSString *)url errorMessage:(NSString *)errorMessage {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE storyboards SET image_status = ?, image_local_path = ?, image_url = ?, image_error_message = ?, updated_at = ? WHERE id = ?", -1, &stmt, NULL);
    ZDBindText(stmt, 1, status ?: @"PENDING");
    ZDBindText(stmt, 2, path);
    ZDBindText(stmt, 3, url);
    ZDBindText(stmt, 4, errorMessage);
    sqlite3_bind_int64(stmt, 5, ZDNow());
    sqlite3_bind_int64(stmt, 6, shotId);
    BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

- (BOOL)updateShotVideoId:(int64_t)shotId status:(NSString *)status localPath:(NSString *)path url:(NSString *)url taskId:(NSString *)taskId errorMessage:(NSString *)errorMessage {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE storyboards SET video_status = ?, video_local_path = ?, video_url = ?, video_task_id = ?, video_error_message = ?, updated_at = ? WHERE id = ?", -1, &stmt, NULL);
    ZDBindText(stmt, 1, status ?: @"PENDING");
    ZDBindText(stmt, 2, path);
    ZDBindText(stmt, 3, url);
    ZDBindText(stmt, 4, taskId);
    ZDBindText(stmt, 5, errorMessage);
    sqlite3_bind_int64(stmt, 6, ZDNow());
    sqlite3_bind_int64(stmt, 7, shotId);
    BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

- (BOOL)replaceStoryboards:(NSArray<ZDStoryboardShot *> *)shots forEpisodeId:(int64_t)episodeId {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, "DELETE FROM storyboards WHERE episode_id = ?", -1, &stmt, NULL);
    sqlite3_bind_int64(stmt, 1, episodeId);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    int64_t now = ZDNow();
    const char *insert =
        "INSERT INTO storyboards (project_id, episode_id, shot_number, scene, action, dialogue, camera, image_prompt, video_prompt, duration_seconds, character_names, character_ids, image_status, video_status, image_url, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', 'PENDING', ?, ?, ?)";
    for (ZDStoryboardShot *shot in shots) {
        sqlite3_stmt *row = NULL;
        sqlite3_prepare_v2(self.db, insert, -1, &row, NULL);
        sqlite3_bind_int64(row, 1, shot.projectId);
        sqlite3_bind_int64(row, 2, shot.episodeId > 0 ? shot.episodeId : episodeId);
        sqlite3_bind_int(row, 3, (int)shot.shotNumber);
        ZDBindText(row, 4, shot.scene ?: @"");
        ZDBindText(row, 5, shot.action ?: @"");
        ZDBindText(row, 6, shot.dialogue ?: @"");
        ZDBindText(row, 7, shot.camera ?: @"");
        ZDBindText(row, 8, shot.imagePrompt ?: @"");
        ZDBindText(row, 9, shot.videoPrompt ?: @"");
        sqlite3_bind_int(row, 10, (int)shot.durationSeconds);
        NSData *names = shot.characterNames ? [NSJSONSerialization dataWithJSONObject:shot.characterNames options:0 error:nil] : nil;
        ZDBindText(row, 11, names ? [[NSString alloc] initWithData:names encoding:NSUTF8StringEncoding] : nil);
        ZDBindText(row, 12, shot.characterIds);
        ZDBindText(row, 13, shot.imageUrl);
        sqlite3_bind_int64(row, 14, now);
        sqlite3_bind_int64(row, 15, now);
        sqlite3_step(row);
        sqlite3_finalize(row);
    }
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

- (BOOL)updateFinalVideoStatus:(NSString *)status projectId:(int64_t)projectId episodeId:(int64_t)episodeId errorMessage:(NSString *)errorMessage localPath:(NSString *)localPath {
    sqlite3_stmt *project = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE projects SET final_video_status = ?, final_video_error_message = ?, final_video_local_path = ?, updated_at = ? WHERE id = ?", -1, &project, NULL);
    ZDBindText(project, 1, status ?: @"PENDING");
    ZDBindText(project, 2, errorMessage);
    ZDBindText(project, 3, localPath);
    sqlite3_bind_int64(project, 4, ZDNow());
    sqlite3_bind_int64(project, 5, projectId);
    sqlite3_step(project);
    sqlite3_finalize(project);
    sqlite3_stmt *episode = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE episodes SET final_video_status = ?, final_video_error_message = ?, final_video_local_path = ?, updated_at = ? WHERE id = ?", -1, &episode, NULL);
    ZDBindText(episode, 1, status ?: @"PENDING");
    ZDBindText(episode, 2, errorMessage);
    ZDBindText(episode, 3, localPath);
    sqlite3_bind_int64(episode, 4, ZDNow());
    sqlite3_bind_int64(episode, 5, episodeId);
    BOOL ok = sqlite3_step(episode) == SQLITE_DONE;
    sqlite3_finalize(episode);
    return ok;
}

- (NSInteger)failInterruptedWorkWithMessage:(NSString *)message {
    int64_t now = ZDNow();
    sqlite3_stmt *projects = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE projects SET status = 'FAILED', error_message = ?, updated_at = ? WHERE status = 'PROCESSING'", -1, &projects, NULL);
    ZDBindText(projects, 1, message);
    sqlite3_bind_int64(projects, 2, now);
    sqlite3_step(projects);
    int changes = sqlite3_changes(self.db);
    sqlite3_finalize(projects);

    sqlite3_stmt *finals = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE projects SET final_video_status = 'FAILED', final_video_error_message = ?, updated_at = ? WHERE final_video_status = 'PROCESSING'", -1, &finals, NULL);
    ZDBindText(finals, 1, message);
    sqlite3_bind_int64(finals, 2, now);
    sqlite3_step(finals);
    sqlite3_finalize(finals);

    sqlite3_stmt *images = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE storyboards SET image_status = 'FAILED', image_error_message = ?, updated_at = ? WHERE image_status = 'PROCESSING'", -1, &images, NULL);
    ZDBindText(images, 1, message);
    sqlite3_bind_int64(images, 2, now);
    sqlite3_step(images);
    sqlite3_finalize(images);

    sqlite3_stmt *videos = NULL;
    sqlite3_prepare_v2(self.db, "UPDATE storyboards SET video_status = 'FAILED', video_error_message = ?, updated_at = ? WHERE video_status = 'PROCESSING'", -1, &videos, NULL);
    ZDBindText(videos, 1, message);
    sqlite3_bind_int64(videos, 2, now);
    sqlite3_step(videos);
    sqlite3_finalize(videos);
    return changes;
}

@end
