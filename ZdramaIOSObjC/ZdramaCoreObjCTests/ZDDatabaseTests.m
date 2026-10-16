#import <XCTest/XCTest.h>
#import "ZDDramaModels.h"
#import "ZDDramaRepository.h"

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

@end
