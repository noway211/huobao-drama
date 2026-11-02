# Objective-C iOS Zdrama Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a parallel pure Objective-C iOS app that runs the same single-episode Agnes drama pipeline as `ZdramaIOS/`.

**Architecture:** `ZdramaCoreObjC` is a static library (SQLite, Agnes, settings, media, generation). `ZdramaObjC` is a UIKit app that only calls use cases and reads the database. The existing Swift app is not modified.

**Tech Stack:** Objective-C, UIKit, libsqlite3, NSURLSession, Security/Keychain, AVFoundation, XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-10-16-ios-objc-zdrama-design.md`

## Global Constraints

- New directory only: `ZdramaIOSObjC/`. Do not edit `ZdramaIOS/`.
- No Swift, GRDB, FMDB, CocoaPods, or Swift Package.
- Display name `视频短剧`. Bundle ID `com.huobao.zdrama.objc`. Minimum iOS 17. Portrait only.
- Database file `Application Support/zdrama.db`, schema version 12, column names copied from `ZdramaIOS/Sources/ZdramaCore/Data/Local/DramaDatabase.swift`.
- Keychain service `com.huobao.zdrama.objc`, account `api_key`.
- Defaults: base URL `https://apihub.agnes-ai.com/`, text `agnes-2.0-flash`, image `agnes-image-2.0-flash`, video `agnes-video-v2.0`, timeout 120.
- Auth header exactly `Authorization: Bearer <apiKey>`.
- Generation stages: `text`, `rewrite`, `storyboard`, `image`, `video`, `final_video`, `full`.
- `full` order is `text → storyboard → image → video → final_video` and stops on the first failure.
- Ping success is HTTP 2xx. Do not require a non-empty `content`.
- Do not add multi-episode UI, character generation, gallery delete, album save, API log, TTS, or background resume.

## Review Focus

- A thinking-model ping with empty `content` and HTTP 200 must count as success. Task 8 tests this.
- A storyboard response that is only `reasoning_content` must fail, while a script response may use that fallback. Task 4 tests both.
- `num_frames` for 1 second is 17, and values above 441 frames cap before the `n*8+1` alignment. Task 3 tests both.
- Cold start must mark `PROCESSING` projects, shots, and final videos as `FAILED`, but must not overwrite `CANCELLED`. Task 6 tests this.
- Image/video generation must skip a shot whose local file still exists and must keep earlier successful shots when a later shot fails. Task 11 tests this.
- Final composition must refuse mismatched tracks and missing files without writing a partial MP4. Task 7 tests the refusal.

## File Structure

```text
ZdramaIOSObjC/
  project.yml
  README.md
  ZdramaCoreObjC/
    ZDPrefix.h
    Domain/ZDDramaModels.h/.m
    Domain/ZDCreateDramaUseCase.h/.m
    Domain/ZDGenerationPreflight.h/.m
    Domain/ZDProjectGenerationLogic.h/.m
    Data/Local/ZDDramaDatabase.h/.m
    Data/Local/ZDDramaRepository.h/.m
    Data/Settings/ZDAgnesSettings.h/.m
    Data/Settings/ZDAgnesSettingsStore.h/.m
    Data/Prompt/ZDPromptDefaults.h/.m
    Data/Prompt/ZDPromptResolver.h/.m
    Data/Remote/ZDChatResponseTextExtractor.h/.m
    Data/Remote/ZDStoryboardJSONParser.h/.m
    Data/Remote/ZDVideoFrameCalculator.h/.m
    Data/Remote/ZDAgnesHTTPClient.h/.m
    Data/Remote/ZDAgnesTextRepository.h/.m
    Data/Remote/ZDAgnesImageRepository.h/.m
    Data/Remote/ZDAgnesVideoRepository.h/.m
    Data/Remote/ZDAgnesStoryboardRepository.h/.m
    Data/Media/ZDGeneratedMediaPaths.h/.m
    Data/Media/ZDMediaDownloadRepository.h/.m
    Data/Media/ZDLocalMp4Composer.h/.m
    Domain/ZDGenerateProjectScriptUseCase.h/.m
    Domain/ZDRewriteEpisodeScriptUseCase.h/.m
    Domain/ZDGenerateStoryboardsUseCase.h/.m
    Domain/ZDGenerateStoryboardImagesUseCase.h/.m
    Domain/ZDGenerateStoryboardVideosUseCase.h/.m
    Domain/ZDComposeFinalVideoUseCase.h/.m
    Generation/ZDGenerationCoordinator.h/.m
  ZdramaObjC/
    App/main.m
    App/ZDAppDelegate.h/.m
    App/ZDAppContainer.h/.m
    Features/Home/ZDHomeViewController.h/.m
    Features/Create/ZDCreateProjectViewController.h/.m
    Features/ProjectList/ZDProjectListViewController.h/.m
    Features/ProjectDetail/ZDProjectDetailViewController.h/.m
    Features/Script/ZDScriptViewController.h/.m
    Features/Storyboard/ZDStoryboardViewController.h/.m
    Features/Gallery/ZDImageGalleryViewController.h/.m
    Features/Player/ZDVideoPlayerViewController.h/.m
    Features/Settings/ZDSettingsViewController.h/.m
    Features/Settings/ZDManagePromptsViewController.h/.m
    Info.plist
  ZdramaCoreObjCTests/
    ZDLogicTests.m
    ZDDatabaseTests.m
    ZDGenerationTests.m
```

Public names below are the contract. Later tasks must not rename them.

---

### Task 1: Project skeleton

**Files:**
- Create: `ZdramaIOSObjC/project.yml`
- Create: `ZdramaIOSObjC/README.md`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/ZDPrefix.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/App/main.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/App/ZDAppDelegate.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/App/ZDAppDelegate.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Info.plist`
- Create: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`

**Interfaces:**
- Consumes: none
- Produces: Xcode schemes `ZdramaObjC` and `ZdramaCoreObjC`; test class `ZDLogicTests`

- [ ] **Step 1: Write the failing test**

```objc
#import <XCTest/XCTest.h>

@interface ZDLogicTests : XCTestCase
@end

@implementation ZDLogicTests

- (void)testSkeletonLinks {
    XCTAssertTrue(YES);
}

@end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOSObjC && xcodebuild -scheme ZdramaCoreObjC -destination 'generic/platform=iOS' build 2>&1 | tail -20`

Expected: FAIL because `project.yml` and the scheme do not exist yet.

- [ ] **Step 3: Write the project files**

`project.yml`:

```yaml
name: ZdramaObjC
options:
  bundleIdPrefix: com.huobao
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    CLANG_ENABLE_OBJC_ARC: YES
    PRODUCT_NAME: 视频短剧
targets:
  ZdramaCoreObjC:
    type: library.static
    platform: iOS
    sources:
      - ZdramaCoreObjC
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.huobao.zdrama.objc.core
        DEFINES_MODULE: YES
    dependencies:
      - sdk: sqlite3.tbd
      - sdk: Security.framework
      - sdk: AVFoundation.framework
  ZdramaObjC:
    type: application
    platform: iOS
    sources:
      - ZdramaObjC
    dependencies:
      - target: ZdramaCoreObjC
    info:
      path: ZdramaObjC/Info.plist
      properties:
        CFBundleDisplayName: 视频短剧
        CFBundleIdentifier: com.huobao.zdrama.objc
        UILaunchScreen: {}
        LSRequiresIPhoneOS: true
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: false
  ZdramaCoreObjCTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - ZdramaCoreObjCTests
    dependencies:
      - target: ZdramaCoreObjC
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.huobao.zdrama.objc.tests
        GENERATE_INFOPLIST_FILE: YES
```

`main.m`:

```objc
#import <UIKit/UIKit.h>
#import "ZDAppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ZDAppDelegate class]));
    }
}
```

`ZDAppDelegate` shows a blank `UINavigationController` with a root view controller titled `视频短剧`. `Info.plist` sets `CFBundleDisplayName` to `视频短剧` and portrait-only orientations. `README.md` says: generate with `xcodegen generate`, then build `ZdramaObjC`.

- [ ] **Step 4: Generate and build**

Run: `cd ZdramaIOSObjC && xcodegen generate && xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/project.yml ZdramaIOSObjC/README.md ZdramaIOSObjC/ZdramaCoreObjC ZdramaIOSObjC/ZdramaObjC ZdramaIOSObjC/ZdramaCoreObjCTests
git commit -m "feat(ios-objc): scaffold Objective-C app and core library"
```

Do not commit `ZdramaObjC.xcodeproj`. Add `ZdramaIOSObjC/*.xcodeproj` to the repo gitignore if the Swift project already ignores generated projects; otherwise add that one line.

---

### Task 2: Domain models

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDDramaModels.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDDramaModels.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`

**Interfaces:**
- Consumes: Task 1 test target
- Produces:
  - `+ (NSString *)ZDProjectStatusFromPersisted:(NSString *)value` returns `DRAFT` for nil/unknown
  - same for `ZDGenerationStageFromPersisted` (`NONE`), `ZDAssetStatusFromPersisted` (`PENDING`), `ZDEpisodeStatusFromPersisted` (`DRAFT`)
  - `@interface ZDDramaProject`, `ZDEpisode`, `ZDStoryboardShot`, `ZDCreateDramaInput` with the properties listed in the Swift structs

- [ ] **Step 1: Write the failing test**

```objc
- (void)testUnknownStatusFallsBack {
    XCTAssertEqualObjects(ZDProjectStatusFromPersisted(nil), @"DRAFT");
    XCTAssertEqualObjects(ZDProjectStatusFromPersisted(@"NOPE"), @"DRAFT");
    XCTAssertEqualObjects(ZDGenerationStageFromPersisted(@"NOPE"), @"NONE");
    XCTAssertEqualObjects(ZDAssetStatusFromPersisted(@"NOPE"), @"PENDING");
    XCTAssertEqualObjects(ZDEpisodeStatusFromPersisted(@"NOPE"), @"DRAFT");
    XCTAssertEqualObjects(ZDProjectStatusFromPersisted(@"PROCESSING"), @"PROCESSING");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOSObjC && xcodebuild -scheme ZdramaCoreObjCTests -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ZdramaCoreObjCTests/ZDLogicTests/testUnknownStatusFallsBack`

Expected: FAIL, `ZDProjectStatusFromPersisted` undeclared. If the simulator name is missing, use the first available iPhone from `xcrun simctl list devices available`.

- [ ] **Step 3: Implement models**

Put the four fallback functions and NSObject model classes in `ZDDramaModels`. Status values are `NSString` constants, not a new enum type. `ZDStoryboardShot.characterNames` is `NSArray<NSString *>`.

- [ ] **Step 4: Run test to verify it passes**

Run the same `xcodebuild ... -only-testing:` command.

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Domain ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m
git commit -m "feat(ios-objc): add drama models and status fallbacks"
```

---

### Task 3: Frame calculator and media paths

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDVideoFrameCalculator.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDVideoFrameCalculator.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDGeneratedMediaPaths.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDGeneratedMediaPaths.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`

**Interfaces:**
- Consumes: none
- Produces:
  - `+ (NSInteger)ZDNumFramesForDuration:(NSInteger)durationSeconds`
  - `ZDGeneratedMediaPaths` methods `-projectDir:`, `-shotImageProjectId:shotId:ext:`, `-shotVideoProjectId:shotId:ext:`, `-finalVideoProjectId:episodeId:`
  - `+ (NSString *)ZDExtensionFromURL:(NSString *)url kind:(NSString *)kind` where kind is `image` or `video`

- [ ] **Step 1: Write the failing test**

```objc
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme ZdramaCoreObjCTests -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ZdramaCoreObjCTests/ZDLogicTests/testNumFramesAndPaths`

Expected: FAIL, symbol not found.

- [ ] **Step 3: Implement the formula**

```objc
NSInteger ZDNumFramesForDuration(NSInteger durationSeconds) {
    NSInteger requested = MAX(durationSeconds, 1) * 24;
    NSInteger capped = MIN(requested, 441);
    NSInteger n = MAX(1, (capped - 1) / 8);
    return n * 8 + 1;
}
```

Extension is valid only when length is 2...5 and every character is ASCII letter or digit. Paths match `GeneratedMediaPaths.swift`.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDVideoFrameCalculator.* ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDGeneratedMediaPaths.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m
git commit -m "feat(ios-objc): add frame calculator and media paths"
```

---

### Task 4: Chat and storyboard parsers

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDChatResponseTextExtractor.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDChatResponseTextExtractor.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDStoryboardJSONParser.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDStoryboardJSONParser.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`

**Interfaces:**
- Consumes: none
- Produces:
  - `+ (NSString *)ZDExtractChatContent:(id)json`
  - `+ (NSString *)ZDExtractFinalChatContent:(id)json`
  - `+ (NSString *)ZDChatFinishReason:(id)json`
  - `+ (NSArray<NSDictionary *> *)ZDParseStoryboardJSON:(NSString *)content error:(NSError **)error`
  - `+ (NSInteger)ZDCountSceneHeaders:(NSString *)script`

- [ ] **Step 1: Write the failing test**

```objc
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
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, extractor undeclared.

- [ ] **Step 3: Port the Swift extractor and parser**

Follow `ChatResponseTextExtractor.swift` candidate order: `output_text`, `choices[].text`, `message.content`, `message.text`, `delta.content`, `output[]`. `ZDExtractChatContent` falls back to `reasoning_content` only after final content is blank. Trim the first non-blank candidate.

`ZDParseStoryboardJSON` takes the substring from the first `[` through the last `]`, then `NSJSONSerialization`. Missing string fields become `@""`. `shot_number` and `duration_seconds` stay strings when present. Scene header regex is `(?m)^##\\s*S\\d+\\b`.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDChatResponseTextExtractor.* ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDStoryboardJSONParser.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m
git commit -m "feat(ios-objc): parse Agnes chat text and storyboard JSON"
```

---

### Task 5: SQLite database and repository

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Local/ZDDramaDatabase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Local/ZDDramaDatabase.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Local/ZDDramaRepository.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Local/ZDDramaRepository.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m`

**Interfaces:**
- Consumes: `ZDDramaProject`, `ZDEpisode`, `ZDStoryboardShot`
- Produces:
  - `+ (sqlite3 *)ZDDramaDatabaseOpenAtPath:(NSString *)path error:(NSError **)error` installs schema and `PRAGMA user_version = 12`
  - `ZDDramaRepository` methods: `-createProject:`, `-getProjects`, `-getProject:`, `-createEpisodeForProjectId:title:content:`, `-getEpisodeForProject:`, `-replaceStoryboards:forEpisodeId:`, `-deleteProject:`

- [ ] **Step 1: Write the failing test**

```objc
- (void)testCreateProjectInsertsEpisodeAndListsNewestFirst {
    ZDDramaRepository *repo = [ZDDramaRepository repositoryWithDatabasePath:@":memory:" filesRoot:@"/tmp/unused"];
    ZDCreateDramaInput *input = [ZDCreateDramaInput inputWithTitle:@"后" prompt:@"创意" style:@"现代短剧" targetAudience:@"大众受众" aspectRatio:@"9:16" shotCount:3 shotDurationSeconds:5];
    int64_t first = [repo createProjectFromInput:input];
    input.title = @"先";
    int64_t second = [repo createProjectFromInput:input];
    NSArray<ZDDramaProject *> *projects = [repo getProjects];
    XCTAssertEqual(projects.firstObject.id, second);
    ZDEpisode *episode = [repo getEpisodeForProject:first];
    XCTAssertEqual(episode.episodeNumber, 1);
    XCTAssertEqualObjects(episode.content, @"创意");
    XCTAssertTrue([repo deleteProject:first]);
    XCTAssertNil([repo getProject:first]);
}
```

Use a temp file path instead of `:memory:` if the repository opens by path. The assertion is: two projects, newest `updated_at` first, episode 1 content equals the prompt, delete removes the project row.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, repository class not found.

- [ ] **Step 3: Implement sqlite3 access**

Copy the four `CREATE TABLE` statements and the characters index from `DramaDatabase.swift` exactly. Open with `sqlite3_open_v2` and `SQLITE_OPEN_FULLMUTEX`. Bind text with `SQLITE_TRANSIENT`. `getProjects` orders by `updated_at DESC`. `createProjectFromInput:` inserts the project as `DRAFT` / `NONE` and episode 1 in one transaction. `deleteProject:` deletes rows in `storyboards`, `episodes`, `characters`, and `projects` for that id.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Local ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m
git commit -m "feat(ios-objc): store projects and episodes in sqlite"
```

---

### Task 6: Settings, prompts, and preflight

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Settings/ZDAgnesSettings.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Settings/ZDAgnesSettings.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Settings/ZDAgnesSettingsStore.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Settings/ZDAgnesSettingsStore.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Prompt/ZDPromptDefaults.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Prompt/ZDPromptDefaults.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Prompt/ZDPromptResolver.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Prompt/ZDPromptResolver.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerationPreflight.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerationPreflight.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`

**Interfaces:**
- Consumes: `ZDStoryboardShot`
- Produces:
  - `+ (ZDAgnesSettings *)ZDAgnesSettingsDefaults`
  - `- (ZDAgnesSettings *)load` / `- (void)save:(ZDAgnesSettings *)settings` on `ZDAgnesSettingsStore`
  - `+ (NSString *)ZDResolvePrompt:(NSString *)custom fallback:(NSString *)fallback`
  - `+ (NSError *)ZDPreflightStage:(NSString *)stage apiKey:(NSString *)apiKey episodeContent:(NSString *)content scriptContent:(NSString *)script shots:(NSArray *)shots fileExists:(BOOL (^)(NSString *))fileExists`

- [ ] **Step 1: Write the failing test**

```objc
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
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, settings class not found.

- [ ] **Step 3: Implement defaults, Keychain, and preflight**

Copy the four prompt strings from `PromptDefaults.swift` verbatim. Blank custom prompt returns the fallback. Settings store uses `NSUserDefaults` suite `com.huobao.zdrama.objc` and Keychain service `com.huobao.zdrama.objc`. Saving a blank base URL, image model, or video model writes the default. Blank text model stays blank only when the caller explicitly saved an empty string after a previous value; the initial default remains `agnes-2.0-flash`.

Preflight messages and rules match `GenerationPreflight.swift`: `final_video` does not require an API key; `rewrite` needs episode content; `storyboard` needs script; `image`/`video`/`final_video` need shots; `video` needs an image file or URL; `final_video` needs an existing local video file.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Settings ZdramaIOSObjC/ZdramaCoreObjC/Data/Prompt ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerationPreflight.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m
git commit -m "feat(ios-objc): add settings, prompts, and generation preflight"
```

---

### Task 7: Final video validation

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDLocalMp4Composer.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDLocalMp4Composer.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m`

**Interfaces:**
- Consumes: `ZDGeneratedMediaPaths`
- Produces: `+ (BOOL)ZDValidateComposeInputs:(NSArray<NSString *> *)paths error:(NSError **)error` and `- (BOOL)composePaths:(NSArray<NSString *> *)paths toURL:(NSURL *)output error:(NSError **)error`

- [ ] **Step 1: Write the failing test**

```objc
- (void)testComposeRejectsEmptyAndMissing {
    NSError *error = nil;
    XCTAssertFalse(ZDValidateComposeInputs(@[], &error));
    XCTAssertEqualObjects(error.localizedDescription, @"请先生成并下载全部分镜视频后再合成成片");
    error = nil;
    XCTAssertFalse(ZDValidateComposeInputs(@[@"/tmp/does-not-exist-shot.mp4"], &error));
    XCTAssertEqualObjects(error.localizedDescription, @"分镜 #1 的本地视频不存在，请重新生成视频");
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, validator undeclared.

- [ ] **Step 3: Implement validation and passthrough export**

`ZDValidateComposeInputs` checks empty list, then each path with `NSFileManager`. Missing path uses 1-based index in `分镜 #N 的本地视频不存在，请重新生成视频`. `composePaths:toURL:error:` calls validation first and returns before creating the output file. The export itself uses `AVMutableComposition` and `AVAssetExportPresetPassthrough`. If video size, preferred transform, or audio sample rate/channel count differ between clips, return `分镜视频参数不一致，无法在本机无转码合成 MP4` and delete any partial output.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDLocalMp4Composer.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDLogicTests.m
git commit -m "feat(ios-objc): reject invalid local mp4 composition"
```

---

### Task 8: Agnes HTTP client and text ping

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesHTTPClient.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesHTTPClient.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesTextRepository.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesTextRepository.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`

**Interfaces:**
- Consumes: `ZDAgnesSettings`
- Produces:
  - `ZDAgnesHTTPClient` `-jsonPOST:body:apiKey:completion:`
  - `ZDAgnesTextRepository` `-pingSettings:completion:` where completion is `void (^)(NSError *error)`
  - A test hook `-initWithSession:` so tests pass a stub `NSURLSession`

- [ ] **Step 1: Write the failing test**

Use a local stub that records the request and returns HTTP 200 with body `{"choices":[{"message":{"content":""}}]}`. Assert the URL is `https://apihub.agnes-ai.com/v1/chat/completions`, header is `Authorization: Bearer test-key`, body `max_tokens` is 8, and completion error is nil.

Add a second stub returning HTTP 401 body `Invalid token`. Assert the error description contains `HTTP 401` and `Invalid token`.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, text repository not found.

- [ ] **Step 3: Implement the client**

Empty API key returns `Agnes API Key is required` and does not call the session. Non-2xx returns `Agnes request failed: HTTP <code>: <body>`. Ping posts user message `ping`, temperature 0, max_tokens 8, model from settings. 2xx is success even when extracted content is empty.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesHTTPClient.* ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesTextRepository.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m
git commit -m "feat(ios-objc): ping Agnes text model on HTTP success"
```

---

### Task 9: Script, rewrite, and storyboard use cases

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateProjectScriptUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateProjectScriptUseCase.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDRewriteEpisodeScriptUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDRewriteEpisodeScriptUseCase.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardsUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardsUseCase.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesStoryboardRepository.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesStoryboardRepository.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Local/ZDDramaRepository.h`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`

**Interfaces:**
- Consumes: repository, text extractor, storyboard parser, prompt resolver
- Produces: `-executeProjectId:settings:completion:` on each use case

- [ ] **Step 1: Write the failing test**

Stub chat to return `{"choices":[{"message":{"content":"剧本正文"}}]}`. After script generation, episode `scriptContent` is `剧本正文`, status is `COMPLETED`, and project `generatedScript` matches. Stub a second response with only `reasoning_content` and `finish_reason` `length` for storyboard. Assert storyboard use case fails and does not delete existing shots.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, use case not found.

- [ ] **Step 3: Implement the three use cases**

Read Swift `GenerateProjectScriptUseCase`, `RewriteEpisodeScriptUseCase`, and `GenerateStoryboardsUseCase` and keep the user prompt fields, temperatures (0.7, 0.7, 0.3), and max tokens (4000, 6000, 10000). Script uses `ZDExtractChatContent`. Storyboard uses `ZDExtractFinalChatContent` and treats blank content plus `finish_reason == length` as truncation failure. Saving storyboards deletes that episode's old rows only after parsing succeeds.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerate*.h ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerate*.m ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDRewrite* ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesStoryboardRepository.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m
git commit -m "feat(ios-objc): generate script and storyboards from Agnes chat"
```

---

### Task 10: Image and video repositories

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesImageRepository.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesImageRepository.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesVideoRepository.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesVideoRepository.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDMediaDownloadRepository.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDMediaDownloadRepository.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`

**Interfaces:**
- Consumes: HTTP client, frame calculator, media paths
- Produces:
  - image repository returns the first URL from `data[0].url` or top-level `url`
  - video repository returns a URL from `metadata.url`, `video_url`, `url`, or `remixed_from_video_id`
  - downloader writes bytes to the destination and does not send the Agnes auth header

- [ ] **Step 1: Write the failing test**

Assert image request JSON has `size = 1024x768`, `n = 1`, and `extra_body.response_format = url`. Assert a completed video create response with `metadata.url` does not send a poll. Assert a processing response sends `GET v1/videos/task-1`. Assert the downloader request has no `Authorization` header.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, image repository not found.

- [ ] **Step 3: Implement request and poll parsing**

Video body uses `num_frames` from `ZDNumFramesForDuration`, `frame_rate = 24`, `width = 768`, `height = 1152`, `mode = ti2vid`. Prompt joins non-empty `videoPrompt`, `action`, and `camera` with `。`, then appends `。请使用中文对白与中文旁白。`. Poll every 10 seconds, at most 60 times. Timeout error is exactly `Video generation timed out`.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesImageRepository.* ZdramaIOSObjC/ZdramaCoreObjC/Data/Remote/ZDAgnesVideoRepository.* ZdramaIOSObjC/ZdramaCoreObjC/Data/Media/ZDMediaDownloadRepository.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m
git commit -m "feat(ios-objc): request Agnes images and videos"
```

---

### Task 11: Image and video use cases

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardImagesUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardImagesUseCase.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardVideosUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardVideosUseCase.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m`

**Interfaces:**
- Consumes: image/video repositories, downloader, repository
- Produces: `-executeProjectId:episodeId:settings:completion:`

- [ ] **Step 1: Write the failing test**

Create two shots. First image request succeeds and writes a temp file. Second returns HTTP 500. Assert shot 1 stays `COMPLETED` with its path, shot 2 is `FAILED`, and the use case error contains `HTTP 500`. Mark shot 1 file as still present and run again. Assert the image endpoint is called once, only for shot 2.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, use case not found.

- [ ] **Step 3: Implement skip and stop rules**

Skip when status is `COMPLETED` and the local file exists. On failure, save that shot's error and return. Do not continue to later shots. Do not mark the successful earlier shot failed.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardImagesUseCase.* ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDGenerateStoryboardVideosUseCase.* ZdramaIOSObjC/ZdramaCoreObjCTests/ZDGenerationTests.m
git commit -m "feat(ios-objc): generate shot images and videos with skip"
```

---

### Task 12: Coordinator and cold start

**Files:**
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Generation/ZDGenerationCoordinator.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Generation/ZDGenerationCoordinator.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDComposeFinalVideoUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDComposeFinalVideoUseCase.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjC/Data/Local/ZDDramaRepository.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m`
- Test: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m`

**Interfaces:**
- Consumes: all use cases and repository
- Produces:
  - `-enqueueProjectId:episodeId:stage:forceRegenerate:`
  - `-cancelProjectId:episodeId:`
  - `-failInterruptedWorkWithMessage:`

- [ ] **Step 1: Write the failing test**

Insert a project with `PROCESSING`, a shot with `image_status = PROCESSING`, and `final_video_status = PROCESSING`. Call `-failInterruptedWorkWithMessage:@"生成任务中断（应用被关闭），请重新开始"`. Assert all three are `FAILED` with that message. Insert another project as `CANCELLED` and assert it stays `CANCELLED`.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, method not found.

- [ ] **Step 3: Implement the queue and recovery**

Use one `NSOperationQueue` with `maxConcurrentOperationCount = 1`. Ignore a duplicate key unless `forceRegenerate` is YES, in which case cancel the old operation first. `full` runs text, storyboard, image, video, then final video, and stops after the first `NSError`. Cancel sets project and episode status to `CANCELLED`. Recovery updates only rows currently `PROCESSING`.

- [ ] **Step 4: Run test to verify it passes**

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Generation ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDComposeFinalVideoUseCase.* ZdramaIOSObjC/ZdramaCoreObjC/Data/Local ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m
git commit -m "feat(ios-objc): queue generation and fail interrupted work"
```

---

### Task 13: App container and navigation shell

**Files:**
- Create: `ZdramaIOSObjC/ZdramaObjC/App/ZDAppContainer.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/App/ZDAppContainer.m`
- Modify: `ZdramaIOSObjC/ZdramaObjC/App/ZDAppDelegate.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Home/ZDHomeViewController.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Home/ZDHomeViewController.m`
- Test: build only. UI behavior is covered by the manual check in Verification.

**Interfaces:**
- Consumes: repository, settings store, coordinator
- Produces: `ZDAppContainer.shared` and a navigation stack rooted at `ZDHomeViewController`

- [ ] **Step 1: Write the app delegate wiring**

On launch, open `Application Support/zdrama.db`, build the repository, settings store, use cases, and coordinator, then call `-failInterruptedWorkWithMessage:`. Set `window.rootViewController` to a navigation controller whose root is home.

- [ ] **Step 2: Build the home screen**

Three buttons: `设置`, `新建`, `项目`. Title `视频短剧`. Subtitle `AI 驱动的短剧创作工具`. Buttons push placeholder view controllers titled with those names until later tasks replace them.

- [ ] **Step 3: Build**

Run: `cd ZdramaIOSObjC && xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ZdramaIOSObjC/ZdramaObjC/App ZdramaIOSObjC/ZdramaObjC/Features/Home
git commit -m "feat(ios-objc): boot the UIKit app from a shared container"
```

---

### Task 14: Settings and prompts screens

**Files:**
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Settings/ZDSettingsViewController.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Settings/ZDSettingsViewController.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Settings/ZDManagePromptsViewController.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Settings/ZDManagePromptsViewController.m`
- Modify: `ZdramaIOSObjC/ZdramaObjC/Features/Home/ZDHomeViewController.m`

**Interfaces:**
- Consumes: `ZDAgnesSettingsStore`, `ZDAgnesTextRepository`, `ZDPromptResolver`
- Produces: settings screen reachable from Home

- [ ] **Step 1: Implement the settings form**

Fields: API Key, Base URL, text model, image model, video model. Buttons: `保存`, `测试连接`, `提示词`. Save trims the key and calls the store before ping. Ping success shows `连接成功`. Failure shows `连接失败：<error>`.

- [ ] **Step 2: Implement prompt tabs**

Three segments: 创作, 改写, 分镜. Save writes the current text. Restore default refills the default prompt. If the text differs from the saved value and the user leaves, present an alert with `继续编辑` and `放弃修改`.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ZdramaIOSObjC/ZdramaObjC/Features/Settings ZdramaIOSObjC/ZdramaObjC/Features/Home
git commit -m "feat(ios-objc): add settings and prompt screens"
```

---

### Task 15: Create and project list

**Files:**
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Create/ZDCreateProjectViewController.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Create/ZDCreateProjectViewController.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/ProjectList/ZDProjectListViewController.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/ProjectList/ZDProjectListViewController.m`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDCreateDramaUseCase.h`
- Create: `ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDCreateDramaUseCase.m`
- Modify: `ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m`

**Interfaces:**
- Consumes: `ZDDramaRepository`
- Produces: `- (int64_t)execute:(ZDCreateDramaInput *)input error:(NSError **)error`

- [ ] **Step 1: Write the failing test**

Empty title returns an error `请填写标题` and inserts nothing. Valid input inserts one project and episode 1.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, use case not found.

- [ ] **Step 3: Implement create and list**

Create screen defaults: style `现代短剧`, audience `大众受众`, aspect `9:16`, shot count 4, duration 5. Title and prompt are required. Shot count and duration must be greater than 0. Success pushes detail with the new id.

List reloads in `viewWillAppear`, ordered by `updatedAt` descending. Swipe delete cancels coordinator work for that project, calls repository delete, and removes `generated/<projectId>/`.

- [ ] **Step 4: Run test and build**

Expected: database test `TEST SUCCEEDED`, app `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaCoreObjC/Domain/ZDCreateDramaUseCase.* ZdramaIOSObjC/ZdramaObjC/Features/Create ZdramaIOSObjC/ZdramaObjC/Features/ProjectList ZdramaIOSObjC/ZdramaCoreObjCTests/ZDDatabaseTests.m
git commit -m "feat(ios-objc): create and list drama projects"
```

---

### Task 16: Project detail

**Files:**
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/ProjectDetail/ZDProjectDetailViewController.h`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/ProjectDetail/ZDProjectDetailViewController.m`
- Modify: `ZdramaIOSObjC/ZdramaObjC/Features/Create/ZDCreateProjectViewController.m`
- Modify: `ZdramaIOSObjC/ZdramaObjC/Features/ProjectList/ZDProjectListViewController.m`

**Interfaces:**
- Consumes: coordinator, preflight, repository
- Produces: detail screen for a project id

- [ ] **Step 1: Implement the detail layout**

Show title, status, current stage, and error. Buttons: `全部生成`, `剧本`, `改写`, `分镜`, `出图`, `出视频`, `成片`, `取消`. Links: `查看剧本`, `查看分镜`, `图库`, `镜头视频`, `播放成片`.

- [ ] **Step 2: Wire actions**

Each generation button runs preflight first. On error, show the preflight message and do not enqueue. If the target content already exists, confirm with `覆盖已有内容？` before enqueueing with `forceRegenerate = YES`. While the project status is `PROCESSING`, disable generation buttons. Reload from the database every 1.5 seconds only while processing.

- [ ] **Step 3: Build**

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ZdramaIOSObjC/ZdramaObjC/Features/ProjectDetail ZdramaIOSObjC/ZdramaObjC/Features/Create ZdramaIOSObjC/ZdramaObjC/Features/ProjectList
git commit -m "feat(ios-objc): add project detail generation actions"
```

---

### Task 17: Script, storyboard, gallery, and player

**Files:**
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Script/ZDScriptViewController.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Storyboard/ZDStoryboardViewController.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Gallery/ZDImageGalleryViewController.m`
- Create: `ZdramaIOSObjC/ZdramaObjC/Features/Player/ZDVideoPlayerViewController.m`
- Modify: `ZdramaIOSObjC/ZdramaObjC/Features/ProjectDetail/ZDProjectDetailViewController.m`

**Interfaces:**
- Consumes: repository read methods and storyboard update method `-updateShotPromptsForShotId:imagePrompt:videoPrompt:`
- Produces: the four viewer screens

- [ ] **Step 1: Implement read-only script and gallery**

Script shows `episode.scriptContent` in a non-editable text view. Gallery shows one image per shot from `imageLocalPath` using `UIImage`. Shots without a file show the shot number only.

- [ ] **Step 2: Implement editable storyboard prompts**

One card per shot. Editable fields are image prompt and video prompt. Save calls the repository update for that shot id only.

- [ ] **Step 3: Implement the player**

Shot mode uses `AVPlayer` with the local video file when it exists, otherwise the remote URL. Previous/next changes `shotNumber` order. Final mode plays `episode.finalVideoLocalPath` and shows `成片不存在` when the file is missing.

- [ ] **Step 4: Build**

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOSObjC/ZdramaObjC/Features/Script ZdramaIOSObjC/ZdramaObjC/Features/Storyboard ZdramaIOSObjC/ZdramaObjC/Features/Gallery ZdramaIOSObjC/ZdramaObjC/Features/Player ZdramaIOSObjC/ZdramaObjC/Features/ProjectDetail
git commit -m "feat(ios-objc): add script, storyboard, gallery, and player"
```

---

### Task 18: README and full verification

**Files:**
- Modify: `ZdramaIOSObjC/README.md`

**Interfaces:**
- Consumes: all previous tasks
- Produces: documented build and test commands

- [ ] **Step 1: Document commands**

```text
cd ZdramaIOSObjC
xcodegen generate
xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build
xcodebuild -scheme ZdramaCoreObjCTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

State that `ZdramaIOS/` is the Swift app and this directory is the Objective-C app.

- [ ] **Step 2: Run the full test command**

Expected: `TEST SUCCEEDED`. If no simulator exists, record the `xcodebuild` error verbatim in the final report and still run the generic build.

- [ ] **Step 3: Commit**

```bash
git add ZdramaIOSObjC/README.md
git commit -m "docs(ios-objc): document Objective-C build and tests"
```

## Self-Review

Spec coverage: skeleton (Task 1), models and schema (Tasks 2, 5), settings and prompts (Tasks 6, 14), parsers and frames (Tasks 3, 4), Agnes text/image/video (Tasks 8-11), composition (Task 7), coordinator and cold start (Task 12), screens (Tasks 13-17), verification (Task 18). No character generation, album save, or background task is planned.

Placeholder scan: every task has a concrete test or build command and a commit. Protocol fields that are already defined in the named Swift source files are referenced by file instead of copied twice.

Type consistency: repository create/list/delete names are fixed in Task 5. Use cases consume those names. Coordinator consumes the use-case execute methods from Tasks 9-12. UI tasks consume the container from Task 13.

## Verification

```text
cd ZdramaIOSObjC
xcodegen generate
xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build
xcodebuild -scheme ZdramaCoreObjCTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```
