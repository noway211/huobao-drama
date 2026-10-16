#import "ZDGenerateStoryboardsUseCase.h"
#import "ZDAgnesStoryboardRepository.h"

static NSError *ZDStoryboardUseCaseError(NSString *message) {
    return [NSError errorWithDomain:@"ZDGenerateStoryboardsUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDGenerateStoryboardsUseCase {
    ZDDramaRepository *_repository;
    ZDAgnesStoryboardRepository *_remote;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session {
    self = [super init];
    if (self) {
        _repository = repository;
        _remote = [[ZDAgnesStoryboardRepository alloc] initWithSession:session];
    }
    return self;
}

- (void)executeProjectId:(int64_t)projectId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    ZDDramaProject *project = [_repository getProject:projectId];
    ZDEpisode *episode = [_repository getEpisodeForProject:projectId];
    if (!project || !episode) { completion(ZDStoryboardUseCaseError(@"Project not found")); return; }
    if ([episode.scriptContent stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        completion(ZDStoryboardUseCaseError(@"请先为本集创作或改写脚本"));
        return;
    }
    [_repository updateProjectTextResult:projectId status:@"PROCESSING" stage:@"storyboard" generatedScript:project.generatedScript errorMessage:nil];
    [_remote generateStoryboardsSettings:settings project:project script:episode.scriptContent completion:^(NSArray<ZDStoryboardShot *> *shots, NSError *error) {
        if (error) {
            [self->_repository updateProjectTextResult:projectId status:@"FAILED" stage:@"storyboard" generatedScript:project.generatedScript errorMessage:error.localizedDescription];
            completion(error);
            return;
        }
        for (ZDStoryboardShot *shot in shots) shot.episodeId = episode.id;
        [self->_repository replaceStoryboards:shots forEpisodeId:episode.id];
        [self->_repository updateProjectTextResult:projectId status:@"COMPLETED" stage:@"storyboard" generatedScript:project.generatedScript errorMessage:nil];
        completion(nil);
    }];
}

@end
