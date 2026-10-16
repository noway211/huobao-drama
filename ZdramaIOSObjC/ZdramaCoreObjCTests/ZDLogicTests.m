#import <XCTest/XCTest.h>
#import "ZDDramaModels.h"

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

@end
