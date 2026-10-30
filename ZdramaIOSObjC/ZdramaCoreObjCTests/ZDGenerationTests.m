#import <XCTest/XCTest.h>
#import "ZDAgnesSettings.h"
#import "ZDAgnesTextRepository.h"
#import "ZDDramaRepository.h"
#import "ZDGenerateProjectScriptUseCase.h"
#import "ZDGenerateStoryboardsUseCase.h"
#import "ZDAgnesImageRepository.h"
#import "ZDAgnesVideoRepository.h"
#import "ZDMediaDownloadRepository.h"
#import "ZDGenerateStoryboardImagesUseCase.h"
#import "ZDGenerateStoryboardVideosUseCase.h"
#import "ZDExtractCharactersUseCase.h"
#import "ZDGenerateCharacterImagesUseCase.h"
#import "ZDGenerateSingleCharacterImageUseCase.h"

@interface ZDStubURLProtocol : NSURLProtocol
@property (class, nonatomic, copy) NSURLRequest *lastRequest;
@property (class, nonatomic, copy) NSArray<NSURLRequest *> *requests;
@property (class, nonatomic) NSInteger statusCode;
@property (class, nonatomic, copy) NSArray<NSNumber *> *statusCodes;
@property (class, nonatomic, copy) NSData *body;
@property (class, nonatomic, copy) NSArray<NSData *> *bodies;
@end

@implementation ZDStubURLProtocol

static NSURLRequest *ZDStubLastRequest;
static NSMutableArray<NSURLRequest *> *ZDStubRequests;
static NSInteger ZDStubStatusCode = 200;
static NSArray<NSNumber *> *ZDStubStatusCodes;
static NSData *ZDStubBody;
static NSArray<NSData *> *ZDStubBodies;

+ (NSURLRequest *)lastRequest { return ZDStubLastRequest; }
+ (void)setLastRequest:(NSURLRequest *)request { ZDStubLastRequest = [request copy]; }
+ (NSArray<NSURLRequest *> *)requests { return ZDStubRequests ?: @[]; }
+ (void)setRequests:(NSArray<NSURLRequest *> *)requests { ZDStubRequests = [requests mutableCopy]; }
+ (NSInteger)statusCode { return ZDStubStatusCode; }
+ (void)setStatusCode:(NSInteger)statusCode { ZDStubStatusCode = statusCode; }
+ (NSArray<NSNumber *> *)statusCodes { return ZDStubStatusCodes; }
+ (void)setStatusCodes:(NSArray<NSNumber *> *)statusCodes { ZDStubStatusCodes = [statusCodes copy]; }
+ (NSData *)body { return ZDStubBody; }
+ (void)setBody:(NSData *)body { ZDStubBody = [body copy]; }
+ (NSArray<NSData *> *)bodies { return ZDStubBodies; }
+ (void)setBodies:(NSArray<NSData *> *)bodies { ZDStubBodies = [bodies copy]; }

+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSMutableURLRequest *recorded = [self.request mutableCopy];
    if (!recorded.HTTPBody && self.request.HTTPBodyStream) {
        NSInputStream *stream = self.request.HTTPBodyStream;
        [stream open];
        NSMutableData *data = [NSMutableData data];
        uint8_t buffer[1024];
        NSInteger count = 0;
        while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        [stream close];
        recorded.HTTPBody = data;
    }
    ZDStubURLProtocol.lastRequest = recorded;
    if (!ZDStubRequests) ZDStubRequests = [NSMutableArray array];
    [ZDStubRequests addObject:recorded];
    NSInteger status = ZDStubURLProtocol.statusCode;
    NSData *body = ZDStubURLProtocol.body;
    NSUInteger index = ZDStubRequests.count - 1;
    if (ZDStubURLProtocol.bodies.count > 0) {
        body = index < ZDStubURLProtocol.bodies.count ? ZDStubURLProtocol.bodies[index] : ZDStubURLProtocol.bodies.lastObject;
    }
    if (ZDStubURLProtocol.statusCodes.count > 0) {
        status = (index < ZDStubURLProtocol.statusCodes.count ? ZDStubURLProtocol.statusCodes[index] : ZDStubURLProtocol.statusCodes.lastObject).integerValue;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                               statusCode:status
                                                              HTTPVersion:@"HTTP/1.1"
                                                             headerFields:@{@"Content-Type": @"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (body) [self.client URLProtocol:self didLoadData:body];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface ZDGenerationTests : XCTestCase
@end

@implementation ZDGenerationTests

- (void)setUp {
    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.body = nil;
    ZDStubURLProtocol.bodies = @[];
    ZDStubURLProtocol.statusCode = 200;
    ZDStubURLProtocol.statusCodes = @[];
}

- (NSURLSession *)stubSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.protocolClasses = @[ZDStubURLProtocol.class];
    return [NSURLSession sessionWithConfiguration:configuration];
}

- (ZDAgnesSettings *)settings {
    ZDAgnesSettings *settings = ZDAgnesSettingsDefaults();
    settings.apiKey = @"test-key";
    settings.textModel = @"agnes-2.0-flash";
    return settings;
}

- (void)testPingSucceedsOnEmptyContent {
    ZDStubURLProtocol.statusCode = 200;
    ZDStubURLProtocol.body = [@"{\"choices\":[{\"message\":{\"content\":\"\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    ZDAgnesTextRepository *repository = [[ZDAgnesTextRepository alloc] initWithSession:[self stubSession]];
    XCTestExpectation *done = [self expectationWithDescription:@"ping"];
    __block NSError *error = nil;
    [repository pingSettings:[self settings] completion:^(NSError *pingError) {
        error = pingError;
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertNil(error);
    NSURLRequest *request = ZDStubURLProtocol.lastRequest;
    XCTAssertEqualObjects(request.URL.absoluteString, @"https://apihub.agnes-ai.com/v1/chat/completions");
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Authorization"], @"Bearer test-key");
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(body[@"max_tokens"], @8);
}

- (void)testPingIncludes401Body {
    ZDStubURLProtocol.statusCode = 401;
    ZDStubURLProtocol.body = [@"Invalid token" dataUsingEncoding:NSUTF8StringEncoding];
    ZDAgnesTextRepository *repository = [[ZDAgnesTextRepository alloc] initWithSession:[self stubSession]];
    XCTestExpectation *done = [self expectationWithDescription:@"ping"];
    __block NSError *error = nil;
    [repository pingSettings:[self settings] completion:^(NSError *pingError) {
        error = pingError;
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertTrue([error.localizedDescription containsString:@"HTTP 401"]);
    XCTAssertTrue([error.localizedDescription containsString:@"Invalid token"]);
}

- (void)testScriptPersistsAndTruncatedStoryboardKeepsShots {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    ZDCreateDramaInput *input = [ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"一个雨夜" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:1 shotDurationSeconds:5];
    int64_t projectId = [repository createProjectFromInput:input];
    ZDEpisode *episode = [repository getEpisodeForProject:projectId];
    ZDStoryboardShot *existing = [ZDStoryboardShot new];
    existing.projectId = projectId;
    existing.episodeId = episode.id;
    existing.shotNumber = 1;
    existing.scene = @"旧街";
    [repository replaceStoryboards:@[existing] forEpisodeId:episode.id];

    ZDStubURLProtocol.statusCode = 200;
    ZDStubURLProtocol.body = [@"{\"choices\":[{\"message\":{\"content\":\"剧本正文\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    ZDGenerateProjectScriptUseCase *scriptUseCase = [[ZDGenerateProjectScriptUseCase alloc] initWithRepository:repository session:[self stubSession]];
    XCTestExpectation *scriptDone = [self expectationWithDescription:@"script"];
    __block NSError *scriptError = nil;
    [scriptUseCase executeProjectId:projectId settings:[self settings] completion:^(NSError *error) {
        scriptError = error;
        [scriptDone fulfill];
    }];
    [self waitForExpectations:@[scriptDone] timeout:2];
    XCTAssertNil(scriptError);
    episode = [repository getEpisodeForProject:projectId];
    XCTAssertEqualObjects(episode.scriptContent, @"剧本正文");
    XCTAssertEqualObjects(episode.status, @"COMPLETED");
    XCTAssertEqualObjects([repository getProject:projectId].generatedScript, @"剧本正文");

    ZDStubURLProtocol.body = [@"{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"reasoning_content\":\"only-think\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    ZDGenerateStoryboardsUseCase *storyboardUseCase = [[ZDGenerateStoryboardsUseCase alloc] initWithRepository:repository session:[self stubSession]];
    XCTestExpectation *storyboardDone = [self expectationWithDescription:@"storyboard"];
    __block NSError *storyboardError = nil;
    [storyboardUseCase executeProjectId:projectId settings:[self settings] completion:^(NSError *error) {
        storyboardError = error;
        [storyboardDone fulfill];
    }];
    [self waitForExpectations:@[storyboardDone] timeout:2];
    XCTAssertNotNil(storyboardError);
    NSArray<ZDStoryboardShot *> *shots = [repository getStoryboardsForEpisode:episode.id];
    XCTAssertEqual(shots.count, 1);
    XCTAssertEqualObjects(shots.firstObject.scene, @"旧街");
}

- (void)testImageVideoRequestsAndDownload {
    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.bodies = nil;
    ZDStubURLProtocol.statusCode = 200;
    ZDStubURLProtocol.body = [@"{\"data\":[{\"url\":\"https://cdn.example/a.jpg\"}]}" dataUsingEncoding:NSUTF8StringEncoding];
    ZDAgnesImageRepository *images = [[ZDAgnesImageRepository alloc] initWithSession:[self stubSession]];
    XCTestExpectation *imageDone = [self expectationWithDescription:@"image"];
    [images generateImageSettings:[self settings] prompt:@"street" completion:^(NSString *url, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(url, @"https://cdn.example/a.jpg");
        [imageDone fulfill];
    }];
    [self waitForExpectations:@[imageDone] timeout:2];
    NSDictionary *imageBody = [NSJSONSerialization JSONObjectWithData:ZDStubURLProtocol.lastRequest.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(imageBody[@"size"], @"1024x768");
    XCTAssertEqualObjects(imageBody[@"n"], @1);
    XCTAssertEqualObjects(imageBody[@"extra_body"][@"response_format"], @"url");

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.body = [@"{\"status\":\"completed\",\"metadata\":{\"url\":\"https://cdn.example/done.mp4\"}}" dataUsingEncoding:NSUTF8StringEncoding];
    ZDAgnesVideoRepository *videos = [[ZDAgnesVideoRepository alloc] initWithSession:[self stubSession] pollDelay:0];
    ZDStoryboardShot *shot = [ZDStoryboardShot new];
    shot.durationSeconds = 1;
    shot.videoPrompt = @"rain";
    shot.imageUrl = @"https://cdn.example/a.jpg";
    XCTestExpectation *completed = [self expectationWithDescription:@"completed video"];
    [videos generateVideoSettings:[self settings] shot:shot completion:^(NSString *url, NSError *error) {
        XCTAssertEqualObjects(url, @"https://cdn.example/done.mp4");
        [completed fulfill];
    }];
    [self waitForExpectations:@[completed] timeout:2];
    XCTAssertEqual(ZDStubURLProtocol.requests.count, 1);

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.bodies = @[
        [@"{\"status\":\"queued\",\"task_id\":\"task-1\",\"video_id\":\"video-1\"}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"{\"status\":\"completed\",\"url\":\"https://cdn.example/polled.mp4\"}" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    XCTestExpectation *polled = [self expectationWithDescription:@"polled video"];
    [videos generateVideoSettings:[self settings] shot:shot completion:^(NSString *url, NSError *error) {
        XCTAssertEqualObjects(url, @"https://cdn.example/polled.mp4");
        [polled fulfill];
    }];
    [self waitForExpectations:@[polled] timeout:2];
    XCTAssertEqual(ZDStubURLProtocol.requests.count, 2);
    XCTAssertEqualObjects(ZDStubURLProtocol.requests[1].HTTPMethod, @"GET");
    NSString *poll = ZDStubURLProtocol.requests[1].URL.absoluteString;
    XCTAssertTrue([poll containsString:@"agnesapi?"]);
    XCTAssertTrue([poll containsString:@"video_id=video-1"]);
    XCTAssertTrue([poll containsString:@"model_name=agnes-video-v2.0"]);
    NSDictionary *videoBody = [NSJSONSerialization JSONObjectWithData:ZDStubURLProtocol.requests[0].HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(videoBody[@"model"], @"agnes-video-v2.0");
    XCTAssertEqualObjects(videoBody[@"seconds"], @"4");
    XCTAssertEqualObjects(videoBody[@"mode"], @"keyframe");
    XCTAssertEqualObjects(videoBody[@"size"], @"720P");
    XCTAssertEqualObjects(videoBody[@"aspect_ratio"], @"16:9");
    XCTAssertEqualObjects(videoBody[@"first_frame"], @"https://cdn.example/a.jpg");
    XCTAssertNil(videoBody[@"num_frames"]);
    XCTAssertNil(videoBody[@"image"]);

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.bodies = nil;
    ZDStubURLProtocol.body = [@"bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    ZDMediaDownloadRepository *downloader = [[ZDMediaDownloadRepository alloc] initWithSession:[self stubSession] filesRoot:root];
    XCTestExpectation *download = [self expectationWithDescription:@"download"];
    [downloader downloadShotImageProjectId:3 shotId:9 url:@"https://cdn.example/a.jpg" completion:^(NSString *path, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue([path hasSuffix:@"/generated/3/shot_9_image.jpg"]);
        [download fulfill];
    }];
    [self waitForExpectations:@[download] timeout:2];
    XCTAssertNil([ZDStubURLProtocol.lastRequest valueForHTTPHeaderField:@"Authorization"]);
}

- (void)testImageUseCaseStopsAndSkipsCompletedFile {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t projectId = [repository createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:2 shotDurationSeconds:5]];
    ZDEpisode *episode = [repository getEpisodeForProject:projectId];
    ZDStoryboardShot *first = [ZDStoryboardShot new];
    first.projectId = projectId;
    first.episodeId = episode.id;
    first.shotNumber = 1;
    first.scene = @"一";
    first.imagePrompt = @"one";
    ZDStoryboardShot *second = [ZDStoryboardShot new];
    second.projectId = projectId;
    second.episodeId = episode.id;
    second.shotNumber = 2;
    second.scene = @"二";
    second.imagePrompt = @"two";
    [repository replaceStoryboards:@[first, second] forEpisodeId:episode.id];
    NSArray<ZDStoryboardShot *> *stored = [repository getStoryboardsForEpisode:episode.id];

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.statusCode = 200;
    ZDStubURLProtocol.statusCodes = @[@200, @200, @500];
    ZDStubURLProtocol.bodies = @[
        [@"{\"data\":[{\"url\":\"https://cdn.example/one.jpg\"}]}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"bytes-1" dataUsingEncoding:NSUTF8StringEncoding],
        [@"fail" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    ZDGenerateStoryboardImagesUseCase *useCase = [[ZDGenerateStoryboardImagesUseCase alloc] initWithRepository:repository session:[self stubSession] filesRoot:root];
    XCTestExpectation *firstRun = [self expectationWithDescription:@"first images"];
    __block NSError *error = nil;
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSError *useCaseError) {
        error = useCaseError;
        [firstRun fulfill];
    }];
    [self waitForExpectations:@[firstRun] timeout:2];
    XCTAssertTrue([error.localizedDescription containsString:@"HTTP 500"]);
    stored = [repository getStoryboardsForEpisode:episode.id];
    XCTAssertEqualObjects(stored[0].imageStatus, @"COMPLETED");
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:stored[0].imageLocalPath]);
    XCTAssertEqualObjects(stored[1].imageStatus, @"FAILED");

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.statusCodes = @[@200, @200];
    ZDStubURLProtocol.bodies = @[
        [@"{\"data\":[{\"url\":\"https://cdn.example/two.jpg\"}]}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"bytes-2" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    XCTestExpectation *secondRun = [self expectationWithDescription:@"retry second"];
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSError *useCaseError) {
        error = useCaseError;
        [secondRun fulfill];
    }];
    [self waitForExpectations:@[secondRun] timeout:2];
    XCTAssertNil(error);
    NSUInteger imagePosts = 0;
    for (NSURLRequest *request in ZDStubURLProtocol.requests) {
        if ([request.URL.absoluteString containsString:@"images/generations"]) imagePosts += 1;
    }
    XCTAssertEqual(imagePosts, 1);
}

- (void)testVideoUseCaseStopsAndSkipsCompletedFile {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t projectId = [repository createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:2 shotDurationSeconds:5]];
    ZDEpisode *episode = [repository getEpisodeForProject:projectId];
    ZDStoryboardShot *first = [ZDStoryboardShot new];
    first.projectId = projectId;
    first.episodeId = episode.id;
    first.shotNumber = 1;
    first.scene = @"一";
    first.videoPrompt = @"one";
    first.imageUrl = @"https://cdn.example/one.jpg";
    ZDStoryboardShot *second = [ZDStoryboardShot new];
    second.projectId = projectId;
    second.episodeId = episode.id;
    second.shotNumber = 2;
    second.scene = @"二";
    second.videoPrompt = @"two";
    second.imageUrl = @"https://cdn.example/two.jpg";
    [repository replaceStoryboards:@[first, second] forEpisodeId:episode.id];

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.statusCodes = @[@200, @200, @500];
    ZDStubURLProtocol.bodies = @[
        [@"{\"status\":\"completed\",\"metadata\":{\"url\":\"https://cdn.example/one.mp4\"}}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"bytes-1" dataUsingEncoding:NSUTF8StringEncoding],
        [@"fail" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    ZDGenerateStoryboardVideosUseCase *useCase = [[ZDGenerateStoryboardVideosUseCase alloc] initWithRepository:repository session:[self stubSession] filesRoot:root];
    XCTestExpectation *firstRun = [self expectationWithDescription:@"first videos"];
    __block NSError *error = nil;
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSError *useCaseError) {
        error = useCaseError;
        [firstRun fulfill];
    }];
    [self waitForExpectations:@[firstRun] timeout:2];
    XCTAssertTrue([error.localizedDescription containsString:@"HTTP 500"]);
    NSArray<ZDStoryboardShot *> *stored = [repository getStoryboardsForEpisode:episode.id];
    XCTAssertEqualObjects(stored[0].videoStatus, @"COMPLETED");
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:stored[0].videoLocalPath]);
    XCTAssertEqualObjects(stored[1].videoStatus, @"FAILED");

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.statusCodes = @[@200, @200];
    ZDStubURLProtocol.bodies = @[
        [@"{\"status\":\"completed\",\"metadata\":{\"url\":\"https://cdn.example/two.mp4\"}}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"bytes-2" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    XCTestExpectation *secondRun = [self expectationWithDescription:@"retry second video"];
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSError *useCaseError) {
        error = useCaseError;
        [secondRun fulfill];
    }];
    [self waitForExpectations:@[secondRun] timeout:2];
    XCTAssertNil(error);
    NSUInteger videoPosts = 0;
    for (NSURLRequest *request in ZDStubURLProtocol.requests) {
        if ([request.URL.absoluteString containsString:@"v1/videos"]) videoPosts += 1;
    }
    XCTAssertEqual(videoPosts, 1);
}

- (void)testExtractMergesSameNameAndKeepsPortrait {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t projectId = [repository createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:2 shotDurationSeconds:5]];
    ZDEpisode *episode = [repository getEpisodeForProject:projectId];
    [repository updateEpisodeScriptContent:@"沈惊川推门而入，林晚站在窗边。" episodeId:episode.id status:@"COMPLETED"];

    ZDCharacter *existing = [ZDCharacter new];
    existing.name = @"沈惊川";
    existing.role = @"男主";
    existing.characterDescription = @"旧描述";
    existing.appearance = @"旧外貌";
    existing.personality = @"旧性格";
    existing.imageStatus = @"COMPLETED";
    existing.imageUrl = @"https://img/shen";
    existing.imageLocalPath = @"/portraits/shen.jpg";
    existing.imageErrorMessage = @"旧错误";
    [repository upsertCharacters:@[existing] projectId:projectId];
    int64_t existingId = [repository getCharactersForProject:projectId].firstObject.id;

    NSString *reply = [NSString stringWithFormat:@"提取结果如下：\n[{\"name\":\"沈惊川\",\"role\":\"\",\"description\":\"\",\"appearance\":\"新外貌\",\"personality\":\"冷静\",\"existing_id\":%lld},{\"name\":\" 林晚 \",\"role\":\"女主\",\"description\":\"窗边\",\"appearance\":\"白衣\",\"personality\":\"\"},{\"name\":\"  \",\"role\":\"龙套\"}]\n以上。", existingId];
    NSData *contentData = [NSJSONSerialization dataWithJSONObject:@[reply] options:0 error:nil];
    NSString *wrapped = [[NSString alloc] initWithData:contentData encoding:NSUTF8StringEncoding];
    NSString *contentJSON = [wrapped substringWithRange:NSMakeRange(1, wrapped.length - 2)];
    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.body = [[NSString stringWithFormat:@"{\"choices\":[{\"message\":{\"content\":%@}}]}", contentJSON] dataUsingEncoding:NSUTF8StringEncoding];

    ZDExtractCharactersUseCase *useCase = [[ZDExtractCharactersUseCase alloc] initWithRepository:repository session:[self stubSession]];
    XCTestExpectation *done = [self expectationWithDescription:@"extract"];
    __block NSInteger count = -1;
    __block NSError *error = nil;
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSInteger extracted, NSError *useCaseError) {
        count = extracted;
        error = useCaseError;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:2];
    XCTAssertNil(error);
    XCTAssertEqual(count, 2);

    NSArray<ZDCharacter *> *rows = [repository getCharactersForProject:projectId];
    XCTAssertEqual(rows.count, 2);
    XCTAssertEqualObjects(rows[0].name, @"沈惊川");
    XCTAssertEqual(rows[0].id, existingId);
    XCTAssertEqualObjects(rows[0].imageStatus, @"COMPLETED");
    XCTAssertEqualObjects(rows[0].imageLocalPath, @"/portraits/shen.jpg");
    XCTAssertEqualObjects(rows[0].imageUrl, @"https://img/shen");
    XCTAssertEqualObjects(rows[0].imageErrorMessage, @"旧错误");
    XCTAssertEqualObjects(rows[0].appearance, @"新外貌");
    XCTAssertEqualObjects(rows[0].role, @"男主");
    XCTAssertEqualObjects(rows[0].characterDescription, @"旧描述");
    XCTAssertEqualObjects(rows[0].personality, @"冷静");
    XCTAssertEqualObjects(rows[1].name, @"林晚");
    XCTAssertEqualObjects(rows[1].role, @"女主");
    XCTAssertEqualObjects(rows[1].appearance, @"白衣");
    XCTAssertNotEqual(rows[1].id, existingId);

    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:ZDStubURLProtocol.lastRequest.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(body[@"temperature"], @0.3);
    XCTAssertEqualObjects(body[@"max_tokens"], @4000);
    NSString *user = body[@"messages"][1][@"content"];
    XCTAssertTrue([user containsString:@"项目中已存在角色：沈惊川。"]);
    XCTAssertTrue([user containsString:@"existing_id"]);
    XCTAssertTrue([user containsString:@"沈惊川推门而入"]);
}

- (void)testExtractRequiresScriptAndRejectsUnparseableReply {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t projectId = [repository createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:2 shotDurationSeconds:5]];
    ZDEpisode *episode = [repository getEpisodeForProject:projectId];
    [repository updateEpisodeScriptContent:@"   " episodeId:episode.id status:@"COMPLETED"];
    [repository updateProjectTextResult:projectId status:@"COMPLETED" stage:@"TEXT" generatedScript:@"project-script-must-not-be-used" errorMessage:nil];

    ZDStubURLProtocol.requests = @[];
    ZDExtractCharactersUseCase *useCase = [[ZDExtractCharactersUseCase alloc] initWithRepository:repository session:[self stubSession]];
    XCTestExpectation *empty = [self expectationWithDescription:@"empty script"];
    __block NSError *error = nil;
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSInteger extracted, NSError *useCaseError) {
        error = useCaseError;
        [empty fulfill];
    }];
    [self waitForExpectations:@[empty] timeout:2];
    XCTAssertEqualObjects(error.localizedDescription, @"请先为本集创作或改写脚本");
    XCTAssertEqual(ZDStubURLProtocol.requests.count, 0);

    [repository updateEpisodeScriptContent:@"只有对白，没有角色表。" episodeId:episode.id status:@"COMPLETED"];
    ZDStubURLProtocol.body = [@"{\"choices\":[{\"message\":{\"content\":\"抱歉，我无法提取。\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    XCTestExpectation *bad = [self expectationWithDescription:@"unparseable"];
    [useCase executeProjectId:projectId episodeId:episode.id settings:[self settings] completion:^(NSInteger extracted, NSError *useCaseError) {
        error = useCaseError;
        [bad fulfill];
    }];
    [self waitForExpectations:@[bad] timeout:2];
    XCTAssertEqualObjects(error.localizedDescription, @"无法解析角色提取结果");
    XCTAssertEqual([repository getCharactersForProject:projectId].count, 0);
}

- (void)testCharacterImagesSkipCompletedContinueAfterFailureAndForceRedraws {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t projectId = [repository createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:2 shotDurationSeconds:5]];
    NSString *existing = [root stringByAppendingPathComponent:@"shen.png"];
    [@"already" writeToFile:existing atomically:YES encoding:NSUTF8StringEncoding error:nil];

    ZDCharacter *kept = [ZDCharacter new];
    kept.name = @"沈惊川";
    kept.appearance = @"黑衣";
    kept.imageStatus = @"COMPLETED";
    kept.imageLocalPath = existing;
    ZDCharacter *fresh = [ZDCharacter new];
    fresh.name = @"林晚";
    fresh.characterDescription = @"窗边";
    fresh.imageStatus = @"PENDING";
    [repository upsertCharacters:@[kept, fresh] projectId:projectId];

    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.statusCode = 500;
    ZDStubURLProtocol.body = [@"fail" dataUsingEncoding:NSUTF8StringEncoding];
    ZDGenerateCharacterImagesUseCase *useCase = [[ZDGenerateCharacterImagesUseCase alloc] initWithRepository:repository session:[self stubSession] filesRoot:root];
    XCTestExpectation *failed = [self expectationWithDescription:@"batch failure"];
    __block NSError *error = nil;
    [useCase executeProjectId:projectId episodeId:1 settings:[self settings] forceRegenerate:NO completion:^(NSInteger generated, NSError *useCaseError) {
        error = useCaseError;
        [failed fulfill];
    }];
    [self waitForExpectations:@[failed] timeout:2];
    XCTAssertTrue([error.localizedDescription containsString:@"HTTP 500"]);
    XCTAssertEqual(ZDStubURLProtocol.requests.count, 1);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:ZDStubURLProtocol.lastRequest.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(body[@"prompt"], @"林晚, 窗边, character turnaround sheet, front view, side view, and back view side by side, full body, high quality");
    XCTAssertEqualObjects(body[@"size"], @"1536x1024");
    NSArray<ZDCharacter *> *stored = [repository getCharactersForProject:projectId];
    XCTAssertEqualObjects(stored[0].imageStatus, @"COMPLETED");
    XCTAssertEqualObjects(stored[0].imageLocalPath, existing);
    XCTAssertEqualObjects(stored[1].imageStatus, @"FAILED");
    XCTAssertTrue([stored[1].imageErrorMessage containsString:@"HTTP 500"]);

    int64_t characterId = stored[0].id;
    ZDStubURLProtocol.requests = @[];
    ZDStubURLProtocol.statusCode = 200;
    ZDStubURLProtocol.statusCodes = @[@200, @200, @200, @200];
    ZDStubURLProtocol.bodies = @[
        [@"{\"data\":[{\"url\":\"https://cdn.example/shen.png\"}]}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"png-bytes" dataUsingEncoding:NSUTF8StringEncoding],
        [@"{\"data\":[{\"url\":\"https://cdn.example/lin.png\"}]}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"lin-bytes" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    XCTestExpectation *forced = [self expectationWithDescription:@"force redraw"];
    __block NSInteger generated = -1;
    [useCase executeProjectId:projectId episodeId:9 settings:[self settings] forceRegenerate:YES completion:^(NSInteger count, NSError *useCaseError) {
        generated = count;
        error = useCaseError;
        [forced fulfill];
    }];
    [self waitForExpectations:@[forced] timeout:2];
    XCTAssertNil(error);
    XCTAssertEqual(generated, 2);
    NSUInteger imagePosts = 0;
    for (NSURLRequest *request in ZDStubURLProtocol.requests) {
        if ([request.URL.absoluteString containsString:@"images/generations"]) imagePosts += 1;
    }
    XCTAssertEqual(imagePosts, 2);
    stored = [repository getCharactersForProject:projectId];
    ZDCharacter *redrawn = nil;
    for (ZDCharacter *row in stored) {
        if (row.id == characterId) redrawn = row;
    }
    XCTAssertEqualObjects(redrawn.imageStatus, @"COMPLETED");
    NSString *expectedSuffix = [NSString stringWithFormat:@"generated/%lld/char_%lld_image.png", projectId, characterId];
    XCTAssertTrue([redrawn.imageLocalPath hasSuffix:expectedSuffix], @"%@", redrawn.imageLocalPath);
    NSString *bytes = [NSString stringWithContentsOfFile:redrawn.imageLocalPath encoding:NSUTF8StringEncoding error:nil];
    XCTAssertEqualObjects(bytes, @"png-bytes");
}

- (void)testCharacterImagesRequireCharactersAndSingleRedrawMarksFailed {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repository = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t projectId = [repository createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"雨夜" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:2 shotDurationSeconds:5]];

    ZDStubURLProtocol.requests = @[];
    ZDGenerateCharacterImagesUseCase *batch = [[ZDGenerateCharacterImagesUseCase alloc] initWithRepository:repository session:[self stubSession] filesRoot:root];
    XCTestExpectation *empty = [self expectationWithDescription:@"no characters"];
    __block NSError *error = nil;
    [batch executeProjectId:projectId episodeId:1 settings:[self settings] forceRegenerate:NO completion:^(NSInteger generated, NSError *useCaseError) {
        error = useCaseError;
        [empty fulfill];
    }];
    [self waitForExpectations:@[empty] timeout:2];
    XCTAssertEqualObjects(error.localizedDescription, @"请先提取角色");
    XCTAssertEqual(ZDStubURLProtocol.requests.count, 0);

    ZDCharacter *character = [ZDCharacter new];
    character.name = @"无名";
    character.imageStatus = @"PENDING";
    [repository upsertCharacters:@[character] projectId:projectId];
    int64_t characterId = [repository getCharactersForProject:projectId].firstObject.id;
    ZDStubURLProtocol.body = [@"{\"data\":[{}]}" dataUsingEncoding:NSUTF8StringEncoding];
    ZDGenerateSingleCharacterImageUseCase *single = [[ZDGenerateSingleCharacterImageUseCase alloc] initWithRepository:repository session:[self stubSession] filesRoot:root];
    XCTestExpectation *redraw = [self expectationWithDescription:@"single failed"];
    [single executeProjectId:projectId characterId:characterId settings:[self settings] completion:^(NSString *path, NSError *useCaseError) {
        error = useCaseError;
        [redraw fulfill];
    }];
    [self waitForExpectations:@[redraw] timeout:2];
    XCTAssertEqualObjects(error.localizedDescription, @"No image URL in Agnes response");
    ZDCharacter *stored = [repository getCharactersForProject:projectId].firstObject;
    XCTAssertEqualObjects(stored.imageStatus, @"FAILED");
    XCTAssertEqualObjects(stored.imageErrorMessage, @"No image URL in Agnes response");
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:ZDStubURLProtocol.lastRequest.HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(body[@"prompt"], @"无名, character portrait, character turnaround sheet, front view, side view, and back view side by side, full body, high quality");
    XCTAssertEqualObjects(body[@"size"], @"1536x1024");
}

@end
