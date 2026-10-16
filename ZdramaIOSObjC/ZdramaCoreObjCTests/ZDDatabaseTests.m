#import <XCTest/XCTest.h>
#import "ZDDramaModels.h"
#import "ZDDramaRepository.h"
#import "ZDGenerationCoordinator.h"

@interface ZDDatabaseTests : XCTestCase
@end

@implementation ZDDatabaseTests

- (void)testCreateProjectInsertsEpisodeAndListsNewestFirst {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    ZDDramaRepository *repo = [ZDDramaRepository repositoryWithDatabasePath:path filesRoot:@"/tmp/unused"];
    ZDCreateDramaInput *input = [ZDCreateDramaInput inputWithTitle:@"后"
                                                           prompt:@"创意"
                                                            style:@"现代短剧"
                                                   targetAudience:@"大众受众"
                                                      aspectRatio:@"9:16"
                                                        shotCount:3
                                              shotDurationSeconds:5];
    int64_t first = [repo createProjectFromInput:input];
    [NSThread sleepForTimeInterval:0.01];
    input.title = @"先";
    int64_t second = [repo createProjectFromInput:input];
    NSArray<ZDDramaProject *> *projects = [repo getProjects];
    XCTAssertEqual(projects.firstObject.id, second);
    ZDEpisode *episode = [repo getEpisodeForProject:first];
    XCTAssertEqual(episode.episodeNumber, 1);
    XCTAssertEqualObjects(episode.content, @"创意");
    XCTAssertTrue([repo deleteProject:first]);
    XCTAssertNil([repo getProject:first]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void)testFailInterruptedWorkLeavesCancelledAlone {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ZDDramaRepository *repo = [ZDDramaRepository repositoryWithDatabasePath:[root stringByAppendingPathComponent:@"zdrama.db"] filesRoot:root];
    int64_t processingId = [repo createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"忙" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:1 shotDurationSeconds:5]];
    int64_t cancelledId = [repo createProjectFromInput:[ZDCreateDramaInput inputWithTitle:@"停" prompt:@"雨" style:@"写实" targetAudience:@"青年" aspectRatio:@"9:16" shotCount:1 shotDurationSeconds:5]];
    [repo updateProjectTextResult:processingId status:@"PROCESSING" stage:@"image" generatedScript:nil errorMessage:nil];
    [repo updateProjectTextResult:cancelledId status:@"CANCELLED" stage:@"image" generatedScript:nil errorMessage:nil];
    ZDEpisode *episode = [repo getEpisodeForProject:processingId];
    ZDStoryboardShot *shot = [ZDStoryboardShot new];
    shot.projectId = processingId;
    shot.episodeId = episode.id;
    shot.shotNumber = 1;
    shot.scene = @"街";
    [repo replaceStoryboards:@[shot] forEpisodeId:episode.id];
    shot = [repo getStoryboardsForEpisode:episode.id].firstObject;
    [repo updateShotImageId:shot.id status:@"PROCESSING" localPath:nil url:nil errorMessage:nil];
    [repo updateFinalVideoStatus:@"PROCESSING" projectId:processingId episodeId:episode.id errorMessage:nil localPath:nil];

    ZDGenerationCoordinator *coordinator = [[ZDGenerationCoordinator alloc] initWithRepository:repo];
    [coordinator failInterruptedWorkWithMessage:@"生成任务中断（应用被关闭），请重新开始"];

    ZDDramaProject *processing = [repo getProject:processingId];
    XCTAssertEqualObjects(processing.status, @"FAILED");
    XCTAssertEqualObjects(processing.errorMessage, @"生成任务中断（应用被关闭），请重新开始");
    XCTAssertEqualObjects(processing.finalVideoStatus, @"FAILED");
    XCTAssertEqualObjects(processing.finalVideoErrorMessage, @"生成任务中断（应用被关闭），请重新开始");
    ZDStoryboardShot *failedShot = [repo getStoryboardsForEpisode:episode.id].firstObject;
    XCTAssertEqualObjects(failedShot.imageStatus, @"FAILED");
    XCTAssertEqualObjects(failedShot.imageErrorMessage, @"生成任务中断（应用被关闭），请重新开始");
    XCTAssertEqualObjects([repo getProject:cancelledId].status, @"CANCELLED");
}

@end
