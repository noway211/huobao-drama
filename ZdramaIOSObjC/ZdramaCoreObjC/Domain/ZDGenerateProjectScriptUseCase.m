#import "ZDGenerateProjectScriptUseCase.h"
#import "ZDAgnesTextRepository.h"

static NSError *ZDScriptUseCaseError(NSString *message) {
    return [NSError errorWithDomain:@"ZDGenerateProjectScriptUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDGenerateProjectScriptUseCase {
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
    ZDDramaProject *project = [_repository getProject:projectId];
    ZDEpisode *episode = [_repository getEpisodeForProject:projectId];
    if (!project || !episode) {
        completion(ZDScriptUseCaseError(project ? @"Episode not found" : @"Project not found"));
        return;
    }
    [_repository updateProjectTextResult:projectId status:@"PROCESSING" stage:@"text" generatedScript:project.generatedScript errorMessage:nil];
    NSString *prompt = episode.content.length ? episode.content : project.prompt;
    [_text generateScriptSettings:settings project:project storyPrompt:prompt completion:^(NSString *script, NSError *error) {
        if (error) {
            [self->_repository updateEpisodeScriptContent:episode.scriptContent episodeId:episode.id status:@"FAILED"];
            [self->_repository updateProjectTextResult:projectId status:@"FAILED" stage:@"text" generatedScript:episode.scriptContent ?: project.generatedScript errorMessage:error.localizedDescription];
            completion(error);
            return;
        }
        [self->_repository updateEpisodeScriptContent:script episodeId:episode.id status:@"COMPLETED"];
        [self->_repository updateProjectTextResult:projectId status:@"COMPLETED" stage:@"text" generatedScript:script errorMessage:nil];
        completion(nil);
    }];
}

@end
