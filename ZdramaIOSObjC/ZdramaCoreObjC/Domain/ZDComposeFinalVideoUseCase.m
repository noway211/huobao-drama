#import "ZDComposeFinalVideoUseCase.h"
#import "ZDGeneratedMediaPaths.h"
#import "ZDLocalMp4Composer.h"

@implementation ZDComposeFinalVideoUseCase {
    ZDDramaRepository *_repository;
    ZDGeneratedMediaPaths *_paths;
    ZDLocalMp4Composer *_composer;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository filesRoot:(NSString *)filesRoot {
    self = [super init];
    if (self) {
        _repository = repository;
        _paths = [[ZDGeneratedMediaPaths alloc] initWithRoot:filesRoot];
        _composer = [ZDLocalMp4Composer new];
    }
    return self;
}

- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId completion:(void (^)(NSError *error))completion {
    NSArray<ZDStoryboardShot *> *shots = [_repository getStoryboardsForEpisode:episodeId];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (ZDStoryboardShot *shot in shots) {
        if (![shot.videoStatus isEqualToString:@"COMPLETED"] || shot.videoLocalPath.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:shot.videoLocalPath]) {
            NSError *error = [NSError errorWithDomain:@"ZDComposeFinalVideoUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: @"请先生成并下载全部分镜视频后再合成成片"}];
            [self->_repository updateFinalVideoStatus:@"FAILED" projectId:projectId episodeId:episodeId errorMessage:error.localizedDescription localPath:nil];
            completion(error);
            return;
        }
        [paths addObject:shot.videoLocalPath];
    }
    if (paths.count == 0) {
        NSError *error = [NSError errorWithDomain:@"ZDComposeFinalVideoUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: @"请先生成分镜"}];
        [_repository updateFinalVideoStatus:@"FAILED" projectId:projectId episodeId:episodeId errorMessage:error.localizedDescription localPath:nil];
        completion(error);
        return;
    }
    NSURL *output = [_paths finalVideoProjectId:projectId episodeId:episodeId];
    NSError *error = nil;
    if (![_composer composePaths:paths toURL:output error:&error]) {
        [_repository updateFinalVideoStatus:@"FAILED" projectId:projectId episodeId:episodeId errorMessage:error.localizedDescription localPath:nil];
        completion(error);
        return;
    }
    [_repository updateFinalVideoStatus:@"COMPLETED" projectId:projectId episodeId:episodeId errorMessage:nil localPath:output.path];
    completion(nil);
}

@end
