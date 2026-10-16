#import "ZDAgnesStoryboardRepository.h"
#import "ZDAgnesHTTPClient.h"
#import "ZDChatResponseTextExtractor.h"
#import "ZDPromptDefaults.h"
#import "ZDPromptResolver.h"
#import "ZDStoryboardJSONParser.h"

static BOOL ZDStoryboardBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDStoryboardError(NSString *message) {
    return [NSError errorWithDomain:@"ZDAgnesStoryboardRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDAgnesStoryboardRepository {
    ZDAgnesHTTPClient *_client;
}

- (instancetype)initWithSession:(NSURLSession *)session {
    self = [super init];
    if (self) _client = [[ZDAgnesHTTPClient alloc] initWithSession:session];
    return self;
}

- (void)generateStoryboardsSettings:(ZDAgnesSettings *)settings project:(ZDDramaProject *)project script:(NSString *)script completion:(void (^)(NSArray<ZDStoryboardShot *> *shots, NSError *error))completion {
    if (ZDStoryboardBlank(settings.apiKey) || ZDStoryboardBlank(settings.textModel)) {
        completion(nil, ZDStoryboardError(ZDStoryboardBlank(settings.apiKey) ? @"Agnes API Key is required" : @"Text model is required"));
        return;
    }
    NSInteger sceneCount = ZDCountSceneHeaders(script ?: @"");
    NSString *hint = sceneCount > 0
        ? [NSString stringWithFormat:@"Script contains %ld scene headers (## S01, ## S02 ...). Generate exactly one storyboard shot per scene, in order.", (long)sceneCount]
        : [NSString stringWithFormat:@"Expected shot count: %ld", (long)project.shotCount];
    NSString *user = [NSString stringWithFormat:@"Project title: %@\nAspect ratio: %@\n%@\nDefault shot duration seconds: %ld\n\nScript:\n%@\n\nReturn only a JSON array. Each item must use these keys: shot_number, scene, action, dialogue, camera, image_prompt, video_prompt, duration_seconds, character_names. character_names must be an array of character names that appear in this shot (use the exact character name strings from the script), or [] if no characters appear.",
                      project.title ?: @"", project.aspectRatio ?: @"", hint, (long)project.shotDurationSeconds, script ?: @""];
    NSDictionary *body = @{
        @"model": settings.textModel,
        @"messages": @[
            @{@"role": @"system", @"content": ZDResolvePrompt(settings.customStoryboardPrompt, ZDPromptDefaults.storyboardPrompt)},
            @{@"role": @"user", @"content": user}
        ],
        @"temperature": @0.3,
        @"max_tokens": @10000
    };
    NSString *base = [settings.baseUrl hasSuffix:@"/"] ? settings.baseUrl : [settings.baseUrl stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:@"v1/chat/completions" relativeToURL:[NSURL URLWithString:base]].absoluteURL;
    [_client jsonPOST:url body:body apiKey:settings.apiKey completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class]) {
            completion(nil, ZDStoryboardError(@"Agnes request failed: invalid response"));
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            NSString *responseBody = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
            completion(nil, ZDStoryboardError(responseBody.length ? [NSString stringWithFormat:@"Agnes request failed: HTTP %ld: %@", (long)response.statusCode, responseBody] : [NSString stringWithFormat:@"Agnes request failed: HTTP %ld", (long)response.statusCode]));
            return;
        }
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *content = ZDExtractFinalChatContent(json);
        if (ZDStoryboardBlank(content) && [ZDChatFinishReason(json) isEqualToString:@"length"]) {
            completion(nil, ZDStoryboardError(@"分镜生成被模型截断，请减少分镜数量或换用支持更长输出的文本模型"));
            return;
        }
        NSError *parseError = nil;
        NSArray<NSDictionary *> *items = ZDParseStoryboardJSON(content, &parseError);
        if (parseError || items.count == 0) {
            completion(nil, parseError ?: ZDStoryboardError(@"Agnes 未返回分镜内容"));
            return;
        }
        NSMutableArray *shots = [NSMutableArray array];
        NSInteger index = 0;
        for (NSDictionary *item in items) {
            ZDStoryboardShot *shot = [ZDStoryboardShot new];
            shot.projectId = project.id;
            shot.shotNumber = [item[@"shot_number"] respondsToSelector:@selector(integerValue)] ? [item[@"shot_number"] integerValue] : index + 1;
            if (shot.shotNumber == 0) shot.shotNumber = index + 1;
            shot.scene = [item[@"scene"] isKindOfClass:NSString.class] ? item[@"scene"] : @"";
            shot.action = [item[@"action"] isKindOfClass:NSString.class] ? item[@"action"] : @"";
            shot.dialogue = [item[@"dialogue"] isKindOfClass:NSString.class] ? item[@"dialogue"] : @"";
            shot.camera = [item[@"camera"] isKindOfClass:NSString.class] ? item[@"camera"] : @"";
            shot.imagePrompt = [item[@"image_prompt"] isKindOfClass:NSString.class] ? item[@"image_prompt"] : @"";
            shot.videoPrompt = [item[@"video_prompt"] isKindOfClass:NSString.class] ? item[@"video_prompt"] : @"";
            shot.durationSeconds = [item[@"duration_seconds"] respondsToSelector:@selector(integerValue)] && [item[@"duration_seconds"] integerValue] > 0 ? [item[@"duration_seconds"] integerValue] : project.shotDurationSeconds;
            shot.characterNames = [item[@"character_names"] isKindOfClass:NSArray.class] ? item[@"character_names"] : @[];
            [shots addObject:shot];
            index += 1;
        }
        completion(shots, nil);
    }];
}

@end
