#import "ZDRewriteEpisodeScriptUseCase.h"
#import "ZDAgnesTextRepository.h"

static NSError *ZDRewriteError(NSString *message) {
    return [NSError errorWithDomain:@"ZDRewriteEpisodeScriptUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDRewriteEpisodeScriptUseCase {
    ZDDramaRepository *_repository;
    ZDAgnesTextRepository *_text;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session {
    self = [super init];
    if (self) {
        _repository = repository;
        _text = [[ZDAgnesTextRepository alloc] initWithSession:session];
    }
    return self;
}

- (void)executeProjectId:(int64_t)projectId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    ZDEpisode *episode = [_repository getEpisodeForProject:projectId];
    if (!episode) { completion(ZDRewriteError(@"Episode not found for project")); return; }
    if (episode.content.length == 0) { completion(ZDRewriteError(@"Episode raw content is empty")); return; }
    [_repository updateEpisodeScriptContent:episode.scriptContent episodeId:episode.id status:@"REWRITING"];
    [_repository updateProjectTextResult:projectId status:@"PROCESSING" stage:@"text" generatedScript:episode.scriptContent errorMessage:nil];
    [_text rewriteScriptSettings:settings rawContent:episode.content completion:^(NSString *script, NSError *error) {
        if (error) {
            [self->_repository updateEpisodeScriptContent:episode.scriptContent episodeId:episode.id status:@"FAILED"];
            [self->_repository updateProjectTextResult:projectId status:@"FAILED" stage:@"text" generatedScript:episode.scriptContent errorMessage:error.localizedDescription];
            completion(error);
            return;
        }
        [self->_repository updateEpisodeScriptContent:script episodeId:episode.id status:@"COMPLETED"];
        [self->_repository updateProjectTextResult:projectId status:@"COMPLETED" stage:@"text" generatedScript:script errorMessage:nil];
        completion(nil);
    }];
}

@end
