#import <XCTest/XCTest.h>
#import "ZDAgnesSettings.h"
#import "ZDAgnesTextRepository.h"

@interface ZDStubURLProtocol : NSURLProtocol
@property (class, nonatomic, copy) NSURLRequest *lastRequest;
@property (class, nonatomic) NSInteger statusCode;
@property (class, nonatomic, copy) NSData *body;
@end

@implementation ZDStubURLProtocol

static NSURLRequest *ZDStubLastRequest;
static NSInteger ZDStubStatusCode = 200;
static NSData *ZDStubBody;

+ (NSURLRequest *)lastRequest { return ZDStubLastRequest; }
+ (void)setLastRequest:(NSURLRequest *)request { ZDStubLastRequest = [request copy]; }
+ (NSInteger)statusCode { return ZDStubStatusCode; }
+ (void)setStatusCode:(NSInteger)statusCode { ZDStubStatusCode = statusCode; }
+ (NSData *)body { return ZDStubBody; }
+ (void)setBody:(NSData *)body { ZDStubBody = [body copy]; }

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
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                               statusCode:ZDStubURLProtocol.statusCode
                                                              HTTPVersion:@"HTTP/1.1"
                                                             headerFields:@{@"Content-Type": @"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (ZDStubURLProtocol.body) [self.client URLProtocol:self didLoadData:ZDStubURLProtocol.body];
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

@end
