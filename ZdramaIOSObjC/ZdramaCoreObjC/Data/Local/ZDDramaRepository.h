#import <Foundation/Foundation.h>
#import "ZDDramaModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDDramaRepository : NSObject
+ (instancetype)repositoryWithDatabasePath:(NSString *)path filesRoot:(NSString *)filesRoot;
- (int64_t)createProjectFromInput:(ZDCreateDramaInput *)input;
- (NSArray<ZDDramaProject *> *)getProjects;
- (nullable ZDDramaProject *)getProject:(int64_t)projectId;
- (int64_t)createEpisodeForProjectId:(int64_t)projectId title:(NSString *)title content:(nullable NSString *)content;
- (nullable ZDEpisode *)getEpisodeForProject:(int64_t)projectId;
- (BOOL)updateEpisodeScriptContent:(nullable NSString *)script episodeId:(int64_t)episodeId status:(NSString *)status;
- (BOOL)updateProjectTextResult:(int64_t)projectId status:(NSString *)status stage:(NSString *)stage generatedScript:(nullable NSString *)script errorMessage:(nullable NSString *)errorMessage;
- (NSArray<ZDStoryboardShot *> *)getStoryboardsForEpisode:(int64_t)episodeId;
- (BOOL)replaceStoryboards:(NSArray<ZDStoryboardShot *> *)shots forEpisodeId:(int64_t)episodeId;
- (BOOL)deleteProject:(int64_t)projectId;
@end

NS_ASSUME_NONNULL_END
