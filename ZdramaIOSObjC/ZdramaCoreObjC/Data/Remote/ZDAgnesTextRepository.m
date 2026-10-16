#import "ZDAgnesTextRepository.h"
#import "ZDAgnesHTTPClient.h"
#import "ZDChatResponseTextExtractor.h"
#import "ZDPromptDefaults.h"
#import "ZDPromptResolver.h"

static BOOL ZDTextBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDTextError(NSString *message) {
    return [NSError errorWithDomain:@"ZDAgnesTextRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDAgnesTextRepository {
    ZDAgnesHTTPClient *_client;
}

- (instancetype)initWithSession:(NSURLSession *)session {
    self = [super init];
    if (self) _client = [[ZDAgnesHTTPClient alloc] initWithSession:session];
    return self;
}

- (void)pingSettings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    if (ZDTextBlank(settings.apiKey)) {
        completion(ZDTextError(@"Agnes API Key is required"));
        return;
    }
    if (ZDTextBlank(settings.textModel)) {
        completion(ZDTextError(@"Text model is required"));
        return;
    }
    NSString *base = settings.baseUrl.length ? settings.baseUrl : @"https://apihub.agnes-ai.com/";
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:@"v1/chat/completions" relativeToURL:[NSURL URLWithString:base]].absoluteURL;
    NSDictionary *body = @{
        @"model": settings.textModel,
        @"messages": @[@{@"role": @"user", @"content": @"ping"}],
        @"temperature": @0,
        @"max_tokens": @8
    };
    [_client jsonPOST:url body:body apiKey:settings.apiKey completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class]) {
            completion(ZDTextError(@"Agnes request failed: invalid response"));
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            NSString *responseBody = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
            NSString *message = responseBody.length == 0
                ? [NSString stringWithFormat:@"Agnes request failed: HTTP %ld", (long)response.statusCode]
                : [NSString stringWithFormat:@"Agnes request failed: HTTP %ld: %@", (long)response.statusCode, responseBody];
            completion(ZDTextError(message));
            return;
        }
        completion(nil);
    }];
}

- (void)postChatSettings:(ZDAgnesSettings *)settings
                messages:(NSArray<NSDictionary *> *)messages
             temperature:(double)temperature
               maxTokens:(NSInteger)maxTokens
              completion:(void (^)(id json, NSError *error))completion {
    if (ZDTextBlank(settings.apiKey)) {
        completion(nil, ZDTextError(@"Agnes API Key is required"));
        return;
    }
    if (ZDTextBlank(settings.textModel)) {
        completion(nil, ZDTextError(@"Text model is required"));
        return;
    }
    NSString *base = settings.baseUrl.length ? settings.baseUrl : @"https://apihub.agnes-ai.com/";
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:@"v1/chat/completions" relativeToURL:[NSURL URLWithString:base]].absoluteURL;
    NSDictionary *body = @{
        @"model": settings.textModel,
        @"messages": messages,
        @"temperature": @(temperature),
        @"max_tokens": @(maxTokens)
    };
    [_client jsonPOST:url body:body apiKey:settings.apiKey completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class]) {
            completion(nil, ZDTextError(@"Agnes request failed: invalid response"));
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            NSString *responseBody = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
            NSString *message = responseBody.length == 0
                ? [NSString stringWithFormat:@"Agnes request failed: HTTP %ld", (long)response.statusCode]
                : [NSString stringWithFormat:@"Agnes request failed: HTTP %ld: %@", (long)response.statusCode, responseBody];
            completion(nil, ZDTextError(message));
            return;
        }
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!json) {
            completion(nil, ZDTextError(@"Agnes request failed: invalid JSON"));
            return;
        }
        completion(json, nil);
    }];
}

- (void)generateScriptSettings:(ZDAgnesSettings *)settings
                       project:(ZDDramaProject *)project
                   storyPrompt:(NSString *)storyPrompt
                    completion:(void (^)(NSString *script, NSError *error))completion {
    NSString *user = [NSString stringWithFormat:@"请根据以下项目信息创作一部短视频短剧剧本。\n\n项目标题：%@\n故事提示词：%@\n风格：%@\n目标受众：%@\n画幅比例：%@\n镜头数量：%ld\n单镜头时长：%ld秒",
                      project.title ?: @"", storyPrompt ?: @"", project.style ?: @"", project.targetAudience ?: @"",
                      project.aspectRatio ?: @"", (long)project.shotCount, (long)project.shotDurationSeconds];
    NSArray *messages = @[
        @{@"role": @"system", @"content": ZDResolvePrompt(settings.customScriptCreatePrompt, ZDPromptDefaults.scriptCreatePrompt)},
        @{@"role": @"user", @"content": user}
    ];
    [self postChatSettings:settings messages:messages temperature:0.7 maxTokens:4000 completion:^(id json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *text = ZDExtractChatContent(json);
        completion(ZDTextBlank(text) ? nil : text, ZDTextBlank(text) ? ZDTextError(@"Agnes 未返回脚本文本，请检查文本模型是否支持 chat/completions") : nil);
    }];
}

- (void)rewriteScriptSettings:(ZDAgnesSettings *)settings
                   rawContent:(NSString *)rawContent
                   completion:(void (^)(NSString *script, NSError *error))completion {
    NSString *user = [NSString stringWithFormat:@"请将以下内容改写为格式化短剧剧本。\n\n【原始内容】\n%@", rawContent ?: @""];
    NSArray *messages = @[
        @{@"role": @"system", @"content": ZDResolvePrompt(settings.customScriptRewritePrompt, ZDPromptDefaults.scriptRewritePrompt)},
        @{@"role": @"user", @"content": user}
    ];
    [self postChatSettings:settings messages:messages temperature:0.7 maxTokens:6000 completion:^(id json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSString *text = ZDExtractChatContent(json);
        completion(ZDTextBlank(text) ? nil : text, ZDTextBlank(text) ? ZDTextError(@"Agnes 未返回改写内容，请检查文本模型是否支持 chat/completions") : nil);
    }];
}

@end
