#import "ZDGenerateStoryboardVideosUseCase.h"
#import "ZDAgnesVideoRepository.h"
#import "ZDMediaDownloadRepository.h"

@implementation ZDGenerateStoryboardVideosUseCase {
    ZDDramaRepository *_repository;
    ZDAgnesVideoRepository *_videos;
    ZDMediaDownloadRepository *_downloads;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session filesRoot:(NSString *)filesRoot {
    self = [super init];
    if (self) {
        _repository = repository;
        _videos = [[ZDAgnesVideoRepository alloc] initWithSession:session pollDelay:10];
        _downloads = [[ZDMediaDownloadRepository alloc] initWithSession:session filesRoot:filesRoot];
    }
    return self;
}

- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    NSArray<ZDStoryboardShot *> *shots = [_repository getStoryboardsForEpisode:episodeId];
    if (shots.count == 0) {
        completion([NSError errorWithDomain:@"ZDGenerateStoryboardVideosUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Generate storyboards before videos"}]);
        return;
    }
    [self generateShots:shots index:0 projectId:projectId settings:settings completion:completion];
}

- (void)generateShots:(NSArray<ZDStoryboardShot *> *)shots index:(NSUInteger)index projectId:(int64_t)projectId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    if (index >= shots.count) { completion(nil); return; }
    ZDStoryboardShot *shot = shots[index];
    if ([shot.videoStatus isEqualToString:@"COMPLETED"] && shot.videoLocalPath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:shot.videoLocalPath]) {
        [self generateShots:shots index:index + 1 projectId:projectId settings:settings completion:completion];
        return;
    }
    [_videos generateVideoSettings:settings shot:shot completion:^(NSString *url, NSError *error) {
        if (error) {
            [self->_repository updateShotVideoId:shot.id status:@"FAILED" localPath:shot.videoLocalPath url:nil taskId:nil errorMessage:error.localizedDescription];
            completion(error);
            return;
        }
        [self->_downloads downloadShotVideoProjectId:projectId shotId:shot.id url:url completion:^(NSString *path, NSError *downloadError) {
            if (downloadError) {
                [self->_repository updateShotVideoId:shot.id status:@"FAILED" localPath:nil url:url taskId:nil errorMessage:downloadError.localizedDescription];
                completion(downloadError);
                return;
            }
            [self->_repository updateShotVideoId:shot.id status:@"COMPLETED" localPath:path url:url taskId:nil errorMessage:nil];
            [self generateShots:shots index:index + 1 projectId:projectId settings:settings completion:completion];
        }];
    }];
}

@end
