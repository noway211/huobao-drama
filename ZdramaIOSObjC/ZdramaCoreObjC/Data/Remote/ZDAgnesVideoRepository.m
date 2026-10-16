#import "ZDAgnesVideoRepository.h"
#import "ZDAgnesHTTPClient.h"
#import "ZDVideoFrameCalculator.h"

static BOOL ZDVideoBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDVideoError(NSString *message) {
    return [NSError errorWithDomain:@"ZDAgnesVideoRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDAgnesVideoRepository {
    NSURLSession *_session;
    ZDAgnesHTTPClient *_client;
    NSTimeInterval _pollDelay;
}

- (instancetype)initWithSession:(NSURLSession *)session pollDelay:(NSTimeInterval)pollDelay {
    self = [super init];
    if (self) {
        _session = session;
        _client = [[ZDAgnesHTTPClient alloc] initWithSession:session];
        _pollDelay = pollDelay;
    }
    return self;
}

- (NSString *)promptForShot:(ZDStoryboardShot *)shot {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *value in @[shot.videoPrompt ?: @"", shot.action ?: @"", shot.camera ?: @""]) {
        if (!ZDVideoBlank(value)) [parts addObject:value];
    }
    return [[parts componentsJoinedByString:@"。"] stringByAppendingString:@"。请使用中文对白与中文旁白。"];
}

- (NSString *)videoURLFrom:(NSDictionary *)json {
    NSString *metadata = [json[@"metadata"] isKindOfClass:NSDictionary.class] ? json[@"metadata"][@"url"] : nil;
    if (!ZDVideoBlank(metadata)) return metadata;
    for (NSString *key in @[@"video_url", @"url", @"remixed_from_video_id"]) {
        if (!ZDVideoBlank(json[key])) return json[key];
    }
    return nil;
}

- (void)generateVideoSettings:(ZDAgnesSettings *)settings shot:(ZDStoryboardShot *)shot completion:(void (^)(NSString *url, NSError *error))completion {
    if (ZDVideoBlank(settings.apiKey) || ZDVideoBlank(settings.videoModel)) {
        completion(nil, ZDVideoError(ZDVideoBlank(settings.apiKey) ? @"Agnes API Key is required" : @"Video model is required"));
        return;
    }
    NSString *image = ZDVideoBlank(shot.imageLocalPath) ? shot.imageUrl : shot.imageLocalPath;
    if (ZDVideoBlank(image)) { completion(nil, ZDVideoError(@"Generate image before video")); return; }
    NSString *base = [settings.baseUrl hasSuffix:@"/"] ? settings.baseUrl : [settings.baseUrl stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:@"v1/videos" relativeToURL:[NSURL URLWithString:base]].absoluteURL;
    NSDictionary *body = @{
        @"model": settings.videoModel,
        @"prompt": [self promptForShot:shot],
        @"num_frames": @(ZDNumFramesForDuration(shot.durationSeconds)),
        @"frame_rate": @24,
        @"width": @768,
        @"height": @1152,
        @"image": image,
        @"mode": @"ti2vid"
    };
    [_client jsonPOST:url body:body apiKey:settings.apiKey completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSDictionary *json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *immediate = [self videoURLFrom:json];
        if ([json[@"status"] isEqual:@"completed"] && !ZDVideoBlank(immediate)) {
            completion(immediate, nil);
            return;
        }
        NSString *taskId = json[@"task_id"] ?: json[@"id"];
        if (ZDVideoBlank(taskId)) { completion(nil, ZDVideoError(@"No task_id/id in Agnes video response")); return; }
        [self pollSettings:settings taskId:taskId remaining:60 completion:completion];
    }];
}

- (void)pollSettings:(ZDAgnesSettings *)settings taskId:(NSString *)taskId remaining:(NSInteger)remaining completion:(void (^)(NSString *url, NSError *error))completion {
    if (remaining == 0) { completion(nil, ZDVideoError(@"Video generation timed out")); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_pollDelay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *base = [settings.baseUrl hasSuffix:@"/"] ? settings.baseUrl : [settings.baseUrl stringByAppendingString:@"/"];
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"v1/videos/%@", taskId] relativeToURL:[NSURL URLWithString:base]].absoluteURL;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"GET";
        [request setValue:[NSString stringWithFormat:@"Bearer %@", settings.apiKey] forHTTPHeaderField:@"Authorization"];
        [[self->_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSDictionary *json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([json[@"status"] isEqual:@"completed"]) {
                NSString *videoURL = [self videoURLFrom:json];
                completion(ZDVideoBlank(videoURL) ? nil : videoURL, ZDVideoBlank(videoURL) ? ZDVideoError(@"Agnes video completed without URL") : nil);
            } else if ([json[@"status"] isEqual:@"failed"]) {
                completion(nil, ZDVideoError([json[@"error"] isKindOfClass:NSString.class] ? json[@"error"] : @"Video generation failed"));
            } else {
                [self pollSettings:settings taskId:taskId remaining:remaining - 1 completion:completion];
            }
        }] resume];
    });
}

@end
