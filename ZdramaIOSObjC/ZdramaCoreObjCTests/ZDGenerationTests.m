#import <XCTest/XCTest.h>
#import "ZDAgnesSettings.h"
#import "ZDAgnesTextRepository.h"
#import "ZDDramaRepository.h"
#import "ZDGenerateProjectScriptUseCase.h"
#import "ZDGenerateStoryboardsUseCase.h"
#import "ZDAgnesImageRepository.h"
#import "ZDAgnesVideoRepository.h"
#import "ZDMediaDownloadRepository.h"

@interface ZDStubURLProtocol : NSURLProtocol
@property (class, nonatomic, copy) NSURLRequest *lastRequest;
@property (class, nonatomic, copy) NSArray<NSURLRequest *> *requests;
@property (class, nonatomic) NSInteger statusCode;
@property (class, nonatomic, copy) NSData *body;
@property (class, nonatomic, copy) NSArray<NSData *> *bodies;
@end

@implementation ZDStubURLProtocol

static NSURLRequest *ZDStubLastRequest;
static NSMutableArray<NSURLRequest *> *ZDStubRequests;
static NSInteger ZDStubStatusCode = 200;
static NSData *ZDStubBody;
static NSArray<NSData *> *ZDStubBodies;

+ (NSURLRequest *)lastRequest { return ZDStubLastRequest; }
+ (void)setLastRequest:(NSURLRequest *)request { ZDStubLastRequest = [request copy]; }
+ (NSArray<NSURLRequest *> *)requests { return ZDStubRequests ?: @[]; }
+ (void)setRequests:(NSArray<NSURLRequest *> *)requests { ZDStubRequests = [requests mutableCopy]; }
+ (NSInteger)statusCode { return ZDStubStatusCode; }
+ (void)setStatusCode:(NSInteger)statusCode { ZDStubStatusCode = statusCode; }
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
    NSData *body = ZDStubURLProtocol.body;
    if (ZDStubURLProtocol.bodies.count > 0) {
        NSUInteger index = ZDStubRequests.count - 1;
        body = index < ZDStubURLProtocol.bodies.count ? ZDStubURLProtocol.bodies[index] : ZDStubURLProtocol.bodies.lastObject;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                               statusCode:ZDStubURLProtocol.statusCode
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
        [@"{\"status\":\"processing\",\"task_id\":\"task-1\"}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"{\"status\":\"completed\",\"metadata\":{\"url\":\"https://cdn.example/polled.mp4\"}}" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    XCTestExpectation *polled = [self expectationWithDescription:@"polled video"];
    [videos generateVideoSettings:[self settings] shot:shot completion:^(NSString *url, NSError *error) {
        XCTAssertEqualObjects(url, @"https://cdn.example/polled.mp4");
        [polled fulfill];
    }];
    [self waitForExpectations:@[polled] timeout:2];
    XCTAssertEqual(ZDStubURLProtocol.requests.count, 2);
    XCTAssertEqualObjects(ZDStubURLProtocol.requests[1].HTTPMethod, @"GET");
    XCTAssertTrue([ZDStubURLProtocol.requests[1].URL.absoluteString hasSuffix:@"v1/videos/task-1"]);

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

@end
