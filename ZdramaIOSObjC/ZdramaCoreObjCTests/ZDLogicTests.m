#import <XCTest/XCTest.h>
#import "ZDDramaModels.h"
#import "ZDVideoFrameCalculator.h"
#import "ZDGeneratedMediaPaths.h"
#import "ZDChatResponseTextExtractor.h"
#import "ZDStoryboardJSONParser.h"
#import "ZDAgnesSettings.h"
#import "ZDPromptDefaults.h"
#import "ZDPromptResolver.h"
#import "ZDGenerationPreflight.h"
#import "ZDLocalMp4Composer.h"

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

- (void)testChatExtractAndStoryboardParse {
    NSDictionary *reasoningOnly = @{@"choices": @[@{@"message": @{@"reasoning_content": @"only-think"}}]};
    XCTAssertEqualObjects(ZDExtractChatContent(reasoningOnly), @"only-think");
    XCTAssertEqualObjects(ZDExtractFinalChatContent(reasoningOnly), @"");
    NSDictionary *parts = @{@"choices": @[@{@"message": @{@"content": @[@{@"text": @"a"}, @{@"text": @"b"}]}}]};
    XCTAssertEqualObjects(ZDExtractFinalChatContent(parts), @"a\nb");
    NSArray *items = ZDParseStoryboardJSON(@"prefix [{\"shot_number\":\"2\",\"scene\":\"街\"}] suffix", nil);
    XCTAssertEqual(items.count, 1);
    XCTAssertEqualObjects(items.firstObject[@"scene"], @"街");
    XCTAssertEqual(ZDCountSceneHeaders(@"## S01 | 内景\n## S02 | 外景"), 2);
    NSError *error = nil;
    XCTAssertNil(ZDParseStoryboardJSON(@"no array", &error));
    XCTAssertNotNil(error);
}

- (void)testDefaultsAndPreflight {
    ZDAgnesSettings *settings = ZDAgnesSettingsDefaults();
    XCTAssertEqualObjects(settings.textModel, @"agnes-2.0-flash");
    XCTAssertEqualObjects(settings.baseUrl, @"https://apihub.agnes-ai.com/");
    XCTAssertEqualObjects(ZDResolvePrompt(@"  ", ZDPromptDefaults.scriptCreatePrompt), ZDPromptDefaults.scriptCreatePrompt);
    NSError *error = ZDPreflightStage(@"final_video", @"", nil, nil, @[], ^BOOL(NSString *path) { return NO; });
    XCTAssertEqualObjects(error.localizedDescription, @"请先生成分镜");
    ZDStoryboardShot *shot = [ZDStoryboardShot new];
    shot.videoLocalPath = @"/missing.mp4";
    error = ZDPreflightStage(@"final_video", @"", nil, nil, @[shot], ^BOOL(NSString *path) { return NO; });
    XCTAssertEqualObjects(error.localizedDescription, @"请先生成并下载全部分镜视频后再合成成片");
    error = ZDPreflightStage(@"text", @"  ", nil, nil, @[], ^BOOL(NSString *path) { return NO; });
    XCTAssertEqualObjects(error.localizedDescription, @"Agnes API Key is required");
}

- (void)testComposeRejectsEmptyAndMissing {
    NSError *error = nil;
    XCTAssertFalse(ZDValidateComposeInputs(@[], &error));
    XCTAssertEqualObjects(error.localizedDescription, @"请先生成并下载全部分镜视频后再合成成片");
    error = nil;
    XCTAssertFalse(ZDValidateComposeInputs(@[@"/tmp/does-not-exist-shot.mp4"], &error));
    XCTAssertEqualObjects(error.localizedDescription, @"分镜 #1 的本地视频不存在，请重新生成视频");
}

@end
