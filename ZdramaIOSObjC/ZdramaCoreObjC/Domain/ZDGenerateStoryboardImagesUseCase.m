#import "ZDGenerateStoryboardImagesUseCase.h"
#import "ZDAgnesImageRepository.h"
#import "ZDMediaDownloadRepository.h"

@implementation ZDGenerateStoryboardImagesUseCase {
    ZDDramaRepository *_repository;
    ZDAgnesImageRepository *_images;
    ZDMediaDownloadRepository *_downloads;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session filesRoot:(NSString *)filesRoot {
    self = [super init];
    if (self) {
        _repository = repository;
        _images = [[ZDAgnesImageRepository alloc] initWithSession:session];
        _downloads = [[ZDMediaDownloadRepository alloc] initWithSession:session filesRoot:filesRoot];
    }
    return self;
}

- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    [self generateShots:[_repository getStoryboardsForEpisode:episodeId] index:0 projectId:projectId settings:settings completion:completion];
}

- (void)generateShots:(NSArray<ZDStoryboardShot *> *)shots index:(NSUInteger)index projectId:(int64_t)projectId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    if (index >= shots.count) { completion(nil); return; }
    ZDStoryboardShot *shot = shots[index];
    if ([shot.imageStatus isEqualToString:@"COMPLETED"] && shot.imageLocalPath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:shot.imageLocalPath]) {
        [self generateShots:shots index:index + 1 projectId:projectId settings:settings completion:completion];
        return;
    }
    [_images generateImageSettings:settings prompt:shot.imagePrompt ?: shot.scene completion:^(NSString *url, NSError *error) {
        if (error) {
            [self->_repository updateShotImageId:shot.id status:@"FAILED" localPath:shot.imageLocalPath url:nil errorMessage:error.localizedDescription];
            completion(error);
            return;
        }
        [self->_downloads downloadShotImageProjectId:projectId shotId:shot.id url:url completion:^(NSString *path, NSError *downloadError) {
            if (downloadError) {
                [self->_repository updateShotImageId:shot.id status:@"FAILED" localPath:nil url:url errorMessage:downloadError.localizedDescription];
                completion(downloadError);
                return;
            }
            [self->_repository updateShotImageId:shot.id status:@"COMPLETED" localPath:path url:url errorMessage:nil];
            [self generateShots:shots index:index + 1 projectId:projectId settings:settings completion:completion];
        }];
    }];
}

@end
