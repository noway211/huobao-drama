#import "ZDGenerationCoordinator.h"
#import "ZDGenerateProjectScriptUseCase.h"
#import "ZDRewriteEpisodeScriptUseCase.h"
#import "ZDGenerateStoryboardsUseCase.h"
#import "ZDGenerateStoryboardImagesUseCase.h"
#import "ZDGenerateStoryboardVideosUseCase.h"
#import "ZDComposeFinalVideoUseCase.h"
#import "ZDAgnesSettingsStore.h"

@implementation ZDGenerationCoordinator {
    ZDDramaRepository *_repository;
    ZDAgnesSettingsStore *_settings;
    ZDGenerateProjectScriptUseCase *_script;
    ZDRewriteEpisodeScriptUseCase *_rewrite;
    ZDGenerateStoryboardsUseCase *_storyboards;
    ZDGenerateStoryboardImagesUseCase *_images;
    ZDGenerateStoryboardVideosUseCase *_videos;
    ZDComposeFinalVideoUseCase *_compose;
    NSOperationQueue *_queue;
    NSMutableDictionary<NSString *, NSBlockOperation *> *_jobs;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository
                           session:(NSURLSession *)session
                         filesRoot:(NSString *)filesRoot
                     settingsStore:(ZDAgnesSettingsStore *)settings {
    self = [super init];
    if (self) {
        _repository = repository;
        _settings = settings;
        _script = [[ZDGenerateProjectScriptUseCase alloc] initWithRepository:repository session:session];
        _rewrite = [[ZDRewriteEpisodeScriptUseCase alloc] initWithRepository:repository session:session];
        _storyboards = [[ZDGenerateStoryboardsUseCase alloc] initWithRepository:repository session:session];
        _images = [[ZDGenerateStoryboardImagesUseCase alloc] initWithRepository:repository session:session filesRoot:filesRoot];
        _videos = [[ZDGenerateStoryboardVideosUseCase alloc] initWithRepository:repository session:session filesRoot:filesRoot];
        _compose = [[ZDComposeFinalVideoUseCase alloc] initWithRepository:repository filesRoot:filesRoot];
        _queue = [NSOperationQueue new];
        _queue.maxConcurrentOperationCount = 1;
        _jobs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository {
    return [self initWithRepository:repository session:NSURLSession.sharedSession filesRoot:@"" settingsStore:[[ZDAgnesSettingsStore alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]];
}

- (NSString *)keyProjectId:(int64_t)projectId episodeId:(int64_t)episodeId stage:(NSString *)stage {
    return [NSString stringWithFormat:@"generation-%lld-%lld-%@", projectId, episodeId, stage ?: @""];
}

- (void)enqueueProjectId:(int64_t)projectId episodeId:(int64_t)episodeId stage:(NSString *)stage forceRegenerate:(BOOL)forceRegenerate {
    NSString *key = [self keyProjectId:projectId episodeId:episodeId stage:stage];
    @synchronized (self) {
        NSBlockOperation *existing = _jobs[key];
        if (existing && !existing.isFinished) {
            if (!forceRegenerate) return;
            [existing cancel];
            [_jobs removeObjectForKey:key];
        }
        NSBlockOperation *operation = [NSBlockOperation new];
        __weak NSBlockOperation *weakOperation = operation;
        [operation addExecutionBlock:^{
            if (weakOperation.isCancelled) return;
            dispatch_semaphore_t gate = dispatch_semaphore_create(0);
            [self runStage:stage projectId:projectId episodeId:episodeId completion:^{
                dispatch_semaphore_signal(gate);
            }];
            dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        }];
        _jobs[key] = operation;
        [_queue addOperation:operation];
    }
}

- (void)runStage:(NSString *)stage projectId:(int64_t)projectId episodeId:(int64_t)episodeId completion:(void (^)(void))completion {
    ZDAgnesSettings *settings = [_settings load];
    void (^finish)(NSError *) = ^(NSError *error) { completion(); };
    if ([stage isEqualToString:@"text"]) {
        [_script executeProjectId:projectId settings:settings completion:finish];
    } else if ([stage isEqualToString:@"rewrite"]) {
        [_rewrite executeProjectId:projectId settings:settings completion:finish];
    } else if ([stage isEqualToString:@"storyboard"]) {
        [_storyboards executeProjectId:projectId settings:settings completion:finish];
    } else if ([stage isEqualToString:@"image"]) {
        [_images executeProjectId:projectId episodeId:episodeId settings:settings completion:finish];
    } else if ([stage isEqualToString:@"video"]) {
        [_videos executeProjectId:projectId episodeId:episodeId settings:settings completion:finish];
    } else if ([stage isEqualToString:@"final_video"]) {
        [_compose executeProjectId:projectId episodeId:episodeId completion:finish];
    } else if ([stage isEqualToString:@"full"]) {
        [self runFullProjectId:projectId episodeId:episodeId settings:settings completion:completion];
    } else {
        ZDDramaProject *project = [_repository getProject:projectId];
        [_repository updateProjectTextResult:projectId status:@"FAILED" stage:@"NONE" generatedScript:project.generatedScript errorMessage:[NSString stringWithFormat:@"Unknown generation stage: %@", stage ?: @""]];
        completion();
    }
}

- (void)runFullProjectId:(int64_t)projectId episodeId:(int64_t)episodeId settings:(ZDAgnesSettings *)settings completion:(void (^)(void))completion {
    [_script executeProjectId:projectId settings:settings completion:^(NSError *error) {
        if (error) { completion(); return; }
        [self->_storyboards executeProjectId:projectId settings:settings completion:^(NSError *storyboardError) {
            if (storyboardError) { completion(); return; }
            [self->_images executeProjectId:projectId episodeId:episodeId settings:settings completion:^(NSError *imageError) {
                if (imageError) { completion(); return; }
                [self->_videos executeProjectId:projectId episodeId:episodeId settings:settings completion:^(NSError *videoError) {
                    if (videoError) { completion(); return; }
                    [self->_compose executeProjectId:projectId episodeId:episodeId completion:^(NSError *composeError) {
                        completion();
                    }];
                }];
            }];
        }];
    }];
}

- (void)cancelProjectId:(int64_t)projectId episodeId:(int64_t)episodeId {
    NSString *prefix = [NSString stringWithFormat:@"generation-%lld-%lld-", projectId, episodeId];
    @synchronized (self) {
        for (NSString *key in _jobs.allKeys) {
            if ([key hasPrefix:prefix]) {
                [_jobs[key] cancel];
                [_jobs removeObjectForKey:key];
            }
        }
    }
    ZDDramaProject *project = [_repository getProject:projectId];
    if (!project) return;
    [_repository updateProjectTextResult:projectId status:@"CANCELLED" stage:project.currentStage generatedScript:project.generatedScript errorMessage:project.errorMessage];
}

- (void)failInterruptedWorkWithMessage:(NSString *)message {
    [_repository failInterruptedWorkWithMessage:message];
}

@end
