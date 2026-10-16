#import <XCTest/XCTest.h>
#import "ZDDramaModels.h"
#import "ZDVideoFrameCalculator.h"
#import "ZDGeneratedMediaPaths.h"

@interface ZDLogicTests : XCTestCase
@end

@implementation ZDLogicTests

- (void)testSkeletonLinks {
    XCTAssertTrue(YES);
}

- (void)testUnknownStatusFallsBack {
    XCTAssertEqualObjects(ZDProjectStatusFromPersisted(nil), @"DRAFT");
    XCTAssertEqualObjects(ZDProjectStatusFromPersisted(@"NOPE"), @"DRAFT");
    XCTAssertEqualObjects(ZDGenerationStageFromPersisted(@"NOPE"), @"NONE");
    XCTAssertEqualObjects(ZDAssetStatusFromPersisted(@"NOPE"), @"PENDING");
    XCTAssertEqualObjects(ZDEpisodeStatusFromPersisted(@"NOPE"), @"DRAFT");
    XCTAssertEqualObjects(ZDProjectStatusFromPersisted(@"PROCESSING"), @"PROCESSING");
}

- (void)testNumFramesAndPaths {
    XCTAssertEqual(ZDNumFramesForDuration(1), 17);
    XCTAssertEqual(ZDNumFramesForDuration(0), 17);
    XCTAssertEqual(ZDNumFramesForDuration(100), 441);
    XCTAssertEqualObjects(ZDExtensionFromURL(@"https://cdn.example/a.jpeg?x=1", @"image"), @"jpeg");
    XCTAssertEqualObjects(ZDExtensionFromURL(@"https://cdn.example/a", @"image"), @"jpg");
    XCTAssertEqualObjects(ZDExtensionFromURL(@"https://cdn.example/a.toolong", @"video"), @"mp4");
    ZDGeneratedMediaPaths *paths = [[ZDGeneratedMediaPaths alloc] initWithRoot:@"/tmp/zdrama"];
    XCTAssertEqualObjects([paths finalVideoProjectId:3 episodeId:9].path,
                          @"/tmp/zdrama/generated/3/episode_9/final_video.mp4");
}

@end
