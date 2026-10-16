#import <Foundation/Foundation.h>
#import "ZDDramaRepository.h"
#import "ZDAgnesSettingsStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDGenerationCoordinator : NSObject
- (instancetype)initWithRepository:(ZDDramaRepository *)repository;
- (instancetype)initWithRepository:(ZDDramaRepository *)repository
                           session:(NSURLSession *)session
                         filesRoot:(NSString *)filesRoot
                     settingsStore:(ZDAgnesSettingsStore *)settings;
- (void)enqueueProjectId:(int64_t)projectId episodeId:(int64_t)episodeId stage:(NSString *)stage forceRegenerate:(BOOL)forceRegenerate;
- (void)cancelProjectId:(int64_t)projectId episodeId:(int64_t)episodeId;
- (void)failInterruptedWorkWithMessage:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
