# Zdrama iOS Native Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone SwiftUI iOS app in `ZdramaIOS/` that creates a single-episode project, talks to Agnes, and produces a local `final_video.mp4`.

**Architecture:** Logic lives in a macOS-testable `ZdramaCore` Swift package (domain, SQLite/GRDB, Agnes client, use cases, coordinator). The iOS app in `ZdramaIOS/App` is SwiftUI screens that call use cases and observe SQLite. No Node backend. Generation is an in-process `actor` queue, not BGProcessing.

**Tech Stack:** Swift 5.9, iOS 17, SwiftUI, GRDB.swift (SPM), URLSession, Keychain, AVFoundation passthrough export, XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-29-ios-zdrama-native-design.md`

## Global Constraints

- Directory: `ZdramaIOS/`. Bundle ID: `com.huobao.zdrama`. Display name: 火宝短剧. iOS 17+.
- Do not call `/api/v1`. Do not import Android/Harmony/KMP code. Do not use SwiftData.
- SQLite file `zdrama.db`, schema version 12, column names copied from Android `DramaLocalDatabase`.
- Enums persist as Android `.name` strings: `DRAFT`, `PROCESSING`, `COMPLETED`, `FAILED`, `CANCELLED`, `NONE`, `TEXT`, `STORYBOARD`, `IMAGE`, `VIDEO`, `FINAL_VIDEO`, `PENDING`, `REWRITING`.
- Agnes defaults: base URL `https://apihub.agnes-ai.com/` (must end with `/`), image `agnes-image-2.0-flash`, video `agnes-video-v2.0`, timeout 120s, text model required empty-by-default.
- Image request: `size=1024x768`, `n=1`, `extra_body.response_format=url`, no `extra_body.image` in v1.
- Video: `frame_rate=24`, `width=768`, `height=1152`, `mode=ti2vid`, poll every 10s up to 60 times, timeout message `Video generation timed out`.
- `num_frames`: `requested = max(duration,1)*24`, `capped = min(requested, 441)`, `n = max(1, (capped-1)/8)`, `num_frames = n*8+1` (1s → 17).
- Image/video stage: first failed shot fails the use case; keep completed shots; full pipeline stops.
- No multi-episode UI, characters UI, album save, per-asset delete, API log, TTS, or BGProcessing.
- Copy prompt strings verbatim from `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/prompt/PromptDefaults.kt`.
- `swift test` must pass without an iOS simulator. Missing Xcode is an environment failure, not a code failure — record the real error.

---

## File Structure

```text
ZdramaIOS/
  Package.swift
  Sources/ZdramaCore/
    Domain/Models/DramaModels.swift
    Domain/UseCases/CreateDramaUseCase.swift
    Domain/UseCases/GenerateProjectScriptUseCase.swift
    Domain/UseCases/RewriteEpisodeScriptUseCase.swift
    Domain/UseCases/GenerateStoryboardsUseCase.swift
    Domain/UseCases/GenerateStoryboardImagesUseCase.swift
    Domain/UseCases/GenerateStoryboardVideosUseCase.swift
    Domain/UseCases/ComposeFinalVideoUseCase.swift
    Domain/UseCases/GenerationPreflight.swift
    Data/Prompt/PromptDefaults.swift
    Data/Prompt/PromptResolver.swift
    Data/Settings/AgnesSettings.swift
    Data/Settings/AgnesSettingsStore.swift
    Data/Local/DramaDatabase.swift
    Data/Local/ProjectLocalDataSource.swift
    Data/Local/EpisodeLocalDataSource.swift
    Data/Local/StoryboardLocalDataSource.swift
    Data/Local/CharacterLocalDataSource.swift
    Data/Local/DramaRepository.swift
    Data/Remote/AgnesHTTPClient.swift
    Data/Remote/AgnesEndpoints.swift
    Data/Remote/ChatResponseTextExtractor.swift
    Data/Remote/StoryboardJSONParser.swift
    Data/Remote/VideoFrameCalculator.swift
    Data/Remote/AgnesTextRepository.swift
    Data/Remote/AgnesStoryboardRepository.swift
    Data/Remote/AgnesImageRepository.swift
    Data/Remote/AgnesVideoRepository.swift
    Data/Media/GeneratedMediaPaths.swift
    Data/Media/MediaDownloadRepository.swift
    Data/Media/LocalMp4Composer.swift
    Generation/GenerationCoordinator.swift
  Tests/ZdramaCoreTests/
    SmokeTests.swift
    DramaModelsTests.swift
    PromptResolverTests.swift
    ChatResponseTextExtractorTests.swift
    StoryboardJSONParserTests.swift
    VideoFrameCalculatorTests.swift
    GenerationPreflightTests.swift
    LocalMp4ComposerTests.swift
    AgnesSettingsStoreTests.swift
    DramaRepositoryTests.swift
    CreateDramaUseCaseTests.swift
    AgnesRemoteRepositoryTests.swift
    ScriptUseCaseTests.swift
    StoryboardUseCaseTests.swift
    ImageVideoUseCaseTests.swift
    GenerationCoordinatorTests.swift
    ProjectDetailLogicTests.swift
  App/
    ZdramaApp.swift
    RootView.swift
    Features/Home/HomeView.swift
    Features/Create/CreateProjectView.swift
    Features/ProjectList/ProjectListView.swift
    Features/ProjectDetail/ProjectDetailView.swift
    Features/ProjectDetail/ProjectDetailViewModel.swift
    Features/Script/ScriptViewerView.swift
    Features/Storyboard/StoryboardViewerView.swift
    Features/Gallery/ImageGalleryView.swift
    Features/Player/VideoPlayerView.swift
    Features/Settings/SettingsView.swift
    Features/Settings/ManagePromptsView.swift
  project.yml
```

Modify: `.gitignore` — add Xcode / SwiftPM / xcuserdata ignores. Do not ignore source under `ZdramaIOS/`.

Spec layout (`ZdramaIOS/Domain`, `ZdramaIOS/Features`) maps onto this tree so `swift test` can run on macOS without an iOS simulator: domain/data/generation live in the `ZdramaCore` library; SwiftUI lives under `ZdramaIOS/App/Features`. Do not also create a parallel `ZdramaIOS/Domain` folder.

---

### Task 1: Swift package shell

**Files:**
- Modify: `.gitignore`
- Create: `ZdramaIOS/Package.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/ZdramaCore.swift`
- Create: `ZdramaIOS/Tests/ZdramaCoreTests/SmokeTests.swift`

**Interfaces:**
- Consumes: empty `ZdramaIOS/` directory.
- Produces: SPM package `ZdramaIOS` with library target `ZdramaCore` (iOS 17 / macOS 14) depending on GRDB, plus test target `ZdramaCoreTests`. Later tasks add files under `Sources/ZdramaCore/` and `Tests/ZdramaCoreTests/`.

- [ ] **Step 1: Write the failing smoke test**

Create `ZdramaIOS/Tests/ZdramaCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import ZdramaCore

final class SmokeTests: XCTestCase {
    func testCoreModuleLoads() {
        XCTAssertEqual(ZdramaCore.moduleName, "ZdramaCore")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter SmokeTests.testCoreModuleLoads`

Expected: FAIL because `ZdramaCore` / `moduleName` does not exist.

- [ ] **Step 3: Add gitignore, Package.swift, and module stub**

Append to repository root `.gitignore` if missing:

```gitignore

# Xcode / Swift
DerivedData/
xcuserdata/
*.xcuserstate
.swiftpm/
ZdramaIOS/.build/
```

Create `ZdramaIOS/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZdramaIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ZdramaCore", targets: ["ZdramaCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.1")
    ],
    targets: [
        .target(
            name: "ZdramaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "ZdramaCoreTests",
            dependencies: ["ZdramaCore"]
        )
    ]
)
```

Create `ZdramaIOS/Sources/ZdramaCore/ZdramaCore.swift`:

```swift
public enum ZdramaCore {
    public static let moduleName = "ZdramaCore"
}
```

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter SmokeTests.testCoreModuleLoads`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .gitignore ZdramaIOS/Package.swift ZdramaIOS/Sources/ZdramaCore/ZdramaCore.swift ZdramaIOS/Tests/ZdramaCoreTests/SmokeTests.swift
git commit -m "feat(ios): add ZdramaCore Swift package shell"
```

---

### Task 2: Domain models

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/Models/DramaModels.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/DramaModelsTests.swift`

**Interfaces:**
- Consumes: Task 1 package.
- Produces: `ProjectStatus`, `GenerationStage`, `AssetStatus`, `EpisodeStatus` with raw values matching Android `.name`; `CreateDramaInput`; `DramaProject`; `Episode`; `StoryboardShot`; `Character`. Unknown raw values map via `init(persisted:)` helpers: project → `draft`, stage → `none`, asset → `pending`, episode → `draft`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ZdramaCore

final class DramaModelsTests: XCTestCase {
    func testPersistedEnumRawValuesMatchAndroid() {
        XCTAssertEqual(ProjectStatus.draft.rawValue, "DRAFT")
        XCTAssertEqual(ProjectStatus.processing.rawValue, "PROCESSING")
        XCTAssertEqual(ProjectStatus.completed.rawValue, "COMPLETED")
        XCTAssertEqual(ProjectStatus.failed.rawValue, "FAILED")
        XCTAssertEqual(ProjectStatus.cancelled.rawValue, "CANCELLED")
        XCTAssertEqual(GenerationStage.none.rawValue, "NONE")
        XCTAssertEqual(GenerationStage.text.rawValue, "TEXT")
        XCTAssertEqual(GenerationStage.storyboard.rawValue, "STORYBOARD")
        XCTAssertEqual(GenerationStage.image.rawValue, "IMAGE")
        XCTAssertEqual(GenerationStage.video.rawValue, "VIDEO")
        XCTAssertEqual(GenerationStage.finalVideo.rawValue, "FINAL_VIDEO")
        XCTAssertEqual(AssetStatus.pending.rawValue, "PENDING")
        XCTAssertEqual(EpisodeStatus.rewriting.rawValue, "REWRITING")
    }

    func testUnknownPersistedValuesFallBack() {
        XCTAssertEqual(ProjectStatus(persisted: "nope"), .draft)
        XCTAssertEqual(GenerationStage(persisted: nil), .none)
        XCTAssertEqual(AssetStatus(persisted: ""), .pending)
        XCTAssertEqual(EpisodeStatus(persisted: "X"), .draft)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter DramaModelsTests`

Expected: FAIL with missing types.

- [ ] **Step 3: Write models**

Create `DramaModels.swift` with public enums `String`-backed as above, plus:

```swift
public struct CreateDramaInput: Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var style: String
    public var targetAudience: String
    public var aspectRatio: String
    public var shotCount: Int
    public var shotDurationSeconds: Int
}

public struct DramaProject: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var prompt: String
    public var style: String
    public var targetAudience: String
    public var aspectRatio: String
    public var shotCount: Int
    public var shotDurationSeconds: Int
    public var status: ProjectStatus
    public var currentStage: GenerationStage
    public var errorMessage: String?
    public var generatedScript: String?
    public var finalVideoStatus: AssetStatus
    public var finalVideoLocalPath: String?
    public var finalVideoErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64
}

public struct Episode: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var projectId: Int64
    public var episodeNumber: Int
    public var title: String
    public var content: String?
    public var scriptContent: String?
    public var status: EpisodeStatus
    public var finalVideoStatus: AssetStatus
    public var finalVideoLocalPath: String?
    public var finalVideoErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64
}

public struct StoryboardShot: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var projectId: Int64
    public var episodeId: Int64?
    public var shotNumber: Int
    public var scene: String
    public var action: String
    public var dialogue: String
    public var camera: String
    public var imagePrompt: String
    public var videoPrompt: String
    public var durationSeconds: Int
    public var characterNames: [String]
    public var characterIds: String?
    public var imageStatus: AssetStatus
    public var imageUrl: String?
    public var imageLocalPath: String?
    public var imageErrorMessage: String?
    public var videoStatus: AssetStatus
    public var videoTaskId: String?
    public var videoUrl: String?
    public var videoLocalPath: String?
    public var videoErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64
}

public struct Character: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var projectId: Int64
    public var episodeId: Int64?
    public var name: String
    public var role: String
    public var description: String
    public var appearance: String
    public var personality: String
    public var imageStatus: AssetStatus
    public var imageUrl: String?
    public var imageLocalPath: String?
    public var imageErrorMessage: String?
    public var createdAt: Int64
    public var updatedAt: Int64
}
```

Add memberwise public inits. For each enum:

```swift
public init(persisted: String?) {
    self = Self(rawValue: persisted ?? "") ?? .draft // or .none / .pending as specified
}
```

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter DramaModelsTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Domain/Models/DramaModels.swift ZdramaIOS/Tests/ZdramaCoreTests/DramaModelsTests.swift
git commit -m "feat(ios): add drama domain models matching Android enums"
```

---

### Task 3: Prompt resolver and defaults

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Prompt/PromptResolver.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Prompt/PromptDefaults.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/PromptResolverTests.swift`

**Interfaces:**
- Consumes: none.
- Produces: `PromptResolver.resolve(custom:default:) -> String`; `PromptDefaults.scriptCreatePrompt`, `.scriptRewritePrompt`, `.characterExtractPrompt`, `.storyboardPrompt` copied verbatim from Android `PromptDefaults.kt`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ZdramaCore

final class PromptResolverTests: XCTestCase {
    func testBlankCustomFallsBack() {
        XCTAssertEqual(PromptResolver.resolve(custom: nil, default: "D"), "D")
        XCTAssertEqual(PromptResolver.resolve(custom: "  ", default: "D"), "D")
        XCTAssertEqual(PromptResolver.resolve(custom: " mine ", default: "D"), "mine")
    }

    func testDefaultsContainSceneHeaderRule() {
        XCTAssertTrue(PromptDefaults.scriptCreatePrompt.contains("## S编号"))
        XCTAssertTrue(PromptDefaults.storyboardPrompt.contains("image_prompt"))
        XCTAssertTrue(PromptDefaults.characterExtractPrompt.contains("主角/配角/龙套"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter PromptResolverTests`

Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
public enum PromptResolver {
    public static func resolve(custom: String?, default defaultValue: String) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}
```

Copy the four Android prompt strings into `PromptDefaults` as `public static let` constants. Do not rephrase.

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter PromptResolverTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Prompt ZdramaIOS/Tests/ZdramaCoreTests/PromptResolverTests.swift
git commit -m "feat(ios): port prompt defaults and blank-fallback resolver"
```

---

### Task 4: Chat response text extractor

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/ChatResponseTextExtractor.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/ChatResponseTextExtractorTests.swift`

**Interfaces:**
- Consumes: JSON as `Any` / `Data`.
- Produces: `ChatResponseTextExtractor.extractFinalContent(_ json: Any) -> String`, `.extract(_ json: Any) -> String` (falls back to `message.reasoning_content`), `.finishReason(_ json: Any) -> String`. Candidate order: `output_text`, `choices[].text`, `message.content` (string or parts array), `message.text`, `delta.content`, `output[]`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ZdramaCore

final class ChatResponseTextExtractorTests: XCTestCase {
    func testExtractsStringContent() throws {
        let json: [String: Any] = [
            "choices": [["message": ["content": "hello script"], "finish_reason": "stop"]]
        ]
        XCTAssertEqual(ChatResponseTextExtractor.extract(json), "hello script")
        XCTAssertEqual(ChatResponseTextExtractor.finishReason(json), "stop")
    }

    func testExtractsContentPartsArray() {
        let json: [String: Any] = [
            "choices": [["message": ["content": [["type": "text", "text": "part-a"], ["text": "part-b"]]]]]
        ]
        XCTAssertEqual(ChatResponseTextExtractor.extractFinalContent(json), "part-a\npart-b")
    }

    func testExtractFallsBackToReasoningContent() {
        let json: [String: Any] = [
            "choices": [["message": ["content": "", "reasoning_content": "hidden"]]]
        ]
        XCTAssertEqual(ChatResponseTextExtractor.extractFinalContent(json), "")
        XCTAssertEqual(ChatResponseTextExtractor.extract(json), "hidden")
    }

    func testOutputTextWins() {
        let json: [String: Any] = ["output_text": "from-output"]
        XCTAssertEqual(ChatResponseTextExtractor.extractFinalContent(json), "from-output")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter ChatResponseTextExtractorTests`

Expected: FAIL.

- [ ] **Step 3: Port extractor**

Implement using the same control flow as `ZdramaAndroid/.../ChatResponseTextExtractor.kt`. Content-part objects: prefer `text`, then `output_text`, then `content`. Join array parts with `\n`. Trim the first non-blank candidate.

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter ChatResponseTextExtractorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Remote/ChatResponseTextExtractor.swift ZdramaIOS/Tests/ZdramaCoreTests/ChatResponseTextExtractorTests.swift
git commit -m "feat(ios): port Agnes chat content extractor"
```

---

### Task 5: Storyboard JSON, frame math, preflight

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/StoryboardJSONParser.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/VideoFrameCalculator.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerationPreflight.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/StoryboardJSONParserTests.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/VideoFrameCalculatorTests.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/GenerationPreflightTests.swift`

**Interfaces:**
- Consumes: `DramaProject`, `Episode`, `StoryboardShot`, `AgnesSettings` (settings type is added in Task 7; until then preflight takes `apiKey: String` plus models). Prefer defining a tiny `PreflightInput` so Task 7 does not rename symbols:

```swift
public struct PreflightInput: Equatable {
    public var apiKey: String
    public var episodeContent: String?
    public var scriptContent: String?
    public var shots: [StoryboardShot]
    public var fileExists: (String) -> Bool
}
```

`fileExists` is not `Equatable`; keep it off Equatable or compare without it. Use a struct without Equatable.

- Produces:
  - `StoryboardJSONParser.parse(_ content: String) throws -> [ParsedStoryboardItem]`
  - `ParsedStoryboardItem` fields: `shotNumber: String?`, `scene`, `action`, `dialogue`, `camera`, `imagePrompt`, `videoPrompt`, `durationSeconds: String?`, `characterNames: [String]?` (JSON keys `shot_number`, `image_prompt`, `video_prompt`, `duration_seconds`, `character_names`)
  - `StoryboardJSONParser.countSceneHeaders(_ script: String) -> Int` using `(?m)^##\\s*S\\d+\\b`
  - `VideoFrameCalculator.numFrames(durationSeconds: Int) -> Int`
  - `enum PreflightError: LocalizedError` and `GenerationPreflight.check(stage:input:)`
  - Stage strings passed to preflight are the coordinator keys: `text`, `rewrite`, `storyboard`, `image`, `video`, `final_video`, `full` (defined in Task 13 as `GenerationStageKey`)

Preflight rules (fail before enqueue):
- All stages except `final_video`: empty `apiKey` → `missingApiKey`
- `rewrite`: blank `episodeContent` → `missingRawContent`
- `storyboard`: blank `scriptContent` → `missingScript`
- `image` / `video` / `final_video`: empty shots → `missingStoryboards`
- `video`: a shot lacks local image file and image URL → `missingImages`
- `final_video`: a shot lacks existing local video file → `missingLocalVideos`

- [ ] **Step 1: Write failing tests**

`VideoFrameCalculatorTests`: `numFrames(1) == 17`, `numFrames(0) == 17`, `numFrames(100) == 441`.

`StoryboardJSONParserTests`:
- Wrapped markdown ```json array``` still parses by slicing first `[` to last `]`.
- Missing JSON array throws a message containing `not JSON`.
- `countSceneHeaders` of `## S01 | 内景` + `## S02 | 外景` is 2.

`GenerationPreflightTests`:
- `stage: "image"` with empty apiKey → `.missingApiKey`
- `stage: "final_video"` with empty apiKey and one shot without video file → `.missingLocalVideos` (not missingApiKey)
- `stage: "rewrite"` with apiKey and nil content → `.missingRawContent`
- `stage: "video"` with image URL present passes even if local path nil.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ZdramaIOS && swift test --filter VideoFrameCalculatorTests --filter StoryboardJSONParserTests --filter GenerationPreflightTests`

Expected: FAIL.

- [ ] **Step 3: Implement parser, calculator, preflight**

`numFrames`:

```swift
public enum VideoFrameCalculator {
    public static let frameRate = 24
    public static let maxNumFrames = 441

    public static func numFrames(durationSeconds: Int) -> Int {
        let requested = max(durationSeconds, 1) * frameRate
        let capped = min(requested, maxNumFrames)
        let n = max(1, (capped - 1) / 8)
        return n * 8 + 1
    }
}
```

Parser: decode `[ParsedStoryboardItem]` from extracted array string with `JSONDecoder` and `convertFromSnakeCase` or explicit `CodingKeys`.

Preflight `LocalizedError.errorDescription` in Chinese matching Android toasts where they exist: `请先为本集创作或改写脚本`, `请先生成分镜`, `请先生成并下载全部分镜视频后再合成成片`. API key: `Agnes API Key is required`.

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter VideoFrameCalculatorTests --filter StoryboardJSONParserTests --filter GenerationPreflightTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Remote/StoryboardJSONParser.swift \
  ZdramaIOS/Sources/ZdramaCore/Data/Remote/VideoFrameCalculator.swift \
  ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerationPreflight.swift \
  ZdramaIOS/Tests/ZdramaCoreTests/StoryboardJSONParserTests.swift \
  ZdramaIOS/Tests/ZdramaCoreTests/VideoFrameCalculatorTests.swift \
  ZdramaIOS/Tests/ZdramaCoreTests/GenerationPreflightTests.swift
git commit -m "feat(ios): add storyboard parser, frame math, and generation preflight"
```

---

### Task 6: Media paths and composer validation

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Media/GeneratedMediaPaths.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Media/LocalMp4Composer.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/LocalMp4ComposerTests.swift`

**Interfaces:**
- Consumes: project/shot/episode ids.
- Produces:

```swift
public struct GeneratedMediaPaths: Sendable {
    public var root: URL // files directory
    public func projectDir(_ projectId: Int64) -> URL
    public func shotImage(projectId: Int64, shotId: Int64, ext: String) -> URL
    public func shotVideo(projectId: Int64, shotId: Int64, ext: String) -> URL
    public func finalVideo(projectId: Int64, episodeId: Int64) -> URL
    // generated/<id>/shot_<shotId>_image.<ext>
    // generated/<id>/shot_<shotId>_video.<ext>
    // generated/<id>/episode_<episodeId>/final_video.mp4
}

public enum LocalMp4ComposerError: LocalizedError, Equatable {
    case emptyInputs
    case missingFile(index: Int)
    case missingVideoTrack
    case incompatibleFormat
    case writeFailed
}

public struct MediaTrackSpec: Equatable, Sendable {
    public var videoMIME: String
    public var width: Int
    public var height: Int
    public var rotationDegrees: Int
    public var audioMIME: String?
    public var sampleRate: Int?
    public var channelCount: Int?
}

public struct LocalMp4Composer: Sendable {
    public func validateInputs(paths: [String], fileExists: (String) -> Bool) throws
    public func validateCompatible(reference: MediaTrackSpec, candidate: MediaTrackSpec) throws
    public func compose(inputPaths: [String], outputPath: String) async throws -> String
}
```

`errorDescription`: emptyInputs → `请先生成并下载全部分镜视频后再合成成片`; missingFile → `分镜 #N 的本地视频不存在，请重新生成视频` (1-based N); incompatibleFormat → `分镜视频参数不一致，无法在本机无转码合成 MP4`; missingVideoTrack → `分镜视频缺少视频轨，无法合成 MP4`; writeFailed → `成片 MP4 写入失败，请重试`.

Video compatible: equal MIME, width, height, rotation. Audio: both nil or both present with equal MIME, sampleRate, channelCount.

`compose` uses `AVMutableComposition` + `AVAssetExportSession` preset `AVAssetExportPresetPassthrough`, deletes existing output first. Tests in this task only cover `validateInputs` / `validateCompatible`.

- [ ] **Step 1: Write failing tests**

```swift
func testEmptyInputs() {
    XCTAssertThrowsError(try LocalMp4Composer().validateInputs(paths: [], fileExists: { _ in true })) { error in
        XCTAssertEqual(error as? LocalMp4ComposerError, .emptyInputs)
    }
}

func testMissingFileIsOneBased() {
    XCTAssertThrowsError(try LocalMp4Composer().validateInputs(paths: ["/a.mp4", "/b.mp4"], fileExists: { $0 == "/a.mp4" })) { error in
        XCTAssertEqual(error as? LocalMp4ComposerError, .missingFile(index: 2))
    }
}

func testIncompatibleResolution() {
    let a = MediaTrackSpec(videoMIME: "video/avc", width: 768, height: 1152, rotationDegrees: 0, audioMIME: nil, sampleRate: nil, channelCount: nil)
    let b = MediaTrackSpec(videoMIME: "video/avc", width: 768, height: 1280, rotationDegrees: 0, audioMIME: nil, sampleRate: nil, channelCount: nil)
    XCTAssertThrowsError(try LocalMp4Composer().validateCompatible(reference: a, candidate: b)) { error in
        XCTAssertEqual(error as? LocalMp4ComposerError, .incompatibleFormat)
    }
}

func testAudioPresenceMismatch() { /* one has audio MIME, other nil → incompatibleFormat */ }

func testShotImagePath() {
    let paths = GeneratedMediaPaths(root: URL(fileURLWithPath: "/tmp/app"))
    XCTAssertEqual(
        paths.shotImage(projectId: 3, shotId: 9, ext: "jpg").path,
        "/tmp/app/generated/3/shot_9_image.jpg"
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter LocalMp4ComposerTests`

Expected: FAIL.

- [ ] **Step 3: Implement paths, validation, and compose**

`compose` must call `validateInputs` then AV passthrough export. Do not leave `fatalError`. Delete output if it exists. Create parent directory. Core tests in this task cover validation only; real mux is exercised later on device.

Extension helper used later by downloads:

```swift
public enum MediaKind { case image, video }
public enum MediaPathHelpers {
    public static func extensionFromURL(_ url: String, kind: MediaKind) -> String {
        // path extension 2...5 alphanumeric, else jpg / mp4
    }
}
```

Put `extensionFromURL` in `GeneratedMediaPaths.swift` and unit test: `https://x/a.PNG` → `PNG` (keep as-is if 2-5 alnum), `https://x/file` → `jpg`/`mp4`.

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter LocalMp4ComposerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Media ZdramaIOS/Tests/ZdramaCoreTests/LocalMp4ComposerTests.swift
git commit -m "feat(ios): add generated media paths and MP4 compose validation"
```

---

### Task 7: Agnes settings store

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Settings/AgnesSettings.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Settings/AgnesSettingsStore.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/AgnesSettingsStoreTests.swift`

**Interfaces:**
- Consumes: `PromptResolver`.
- Produces:

```swift
public struct AgnesSettings: Equatable, Sendable {
    public var apiKey: String
    public var baseUrl: String
    public var textModel: String
    public var imageModel: String
    public var videoModel: String
    public var requestTimeoutSeconds: Int
    public var customScriptCreatePrompt: String?
    public var customScriptRewritePrompt: String?
    public var customCharacterExtractPrompt: String?
    public var customStoryboardPrompt: String?
    public static let defaultBaseURL = "https://apihub.agnes-ai.com/"
    public static let defaultImageModel = "agnes-image-2.0-flash"
    public static let defaultVideoModel = "agnes-video-v2.0"
    public static let defaultTimeoutSeconds = 120
    public static func defaults() -> AgnesSettings
}

public protocol KeychainStore: Sendable {
    func get(_ key: String) throws -> String?
    func set(_ key: String, value: String) throws
}

public final class AgnesSettingsStore: @unchecked Sendable {
    public init(defaults: UserDefaults, keychain: KeychainStore)
    public func load() -> AgnesSettings
    public func save(_ settings: AgnesSettings)
    public func hasApiKey() -> Bool
    public static func normalizeBaseURL(_ value: String) -> String
}
```

UserDefaults keys: `base_url`, `text_model`, `image_model`, `video_model`, `timeout_seconds`, `custom_script_create_prompt`, `custom_script_rewrite_prompt`, `custom_character_extract_prompt`, `custom_storyboard_prompt`. Keychain key: `api_key`. Save always writes `requestTimeoutSeconds` default 120. Blank custom prompts stored as nil. `normalizeBaseURL` trims, falls back to default, appends `/`.

- [ ] **Step 1: Write failing tests using a fake keychain and `UserDefaults(suiteName:)`**

Cover: defaults when empty; save/load round-trip of apiKey; base URL without slash gains `/`; blank custom prompt loads as nil; `hasApiKey` false for whitespace.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter AgnesSettingsStoreTests`

Expected: FAIL.

- [ ] **Step 3: Implement settings + `InMemoryKeychainStore` in the test target (or as internal test helper). Production `SystemKeychainStore` uses Security framework `kSecClassGenericPassword`, service `com.huobao.zdrama`.**

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter AgnesSettingsStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Settings ZdramaIOS/Tests/ZdramaCoreTests/AgnesSettingsStoreTests.swift
git commit -m "feat(ios): store Agnes settings in Keychain and UserDefaults"
```

---

### Task 8: SQLite schema and DramaRepository

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Local/DramaDatabase.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Local/ProjectLocalDataSource.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Local/EpisodeLocalDataSource.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Local/StoryboardLocalDataSource.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Local/CharacterLocalDataSource.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Local/DramaRepository.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/DramaRepositoryTests.swift`

**Interfaces:**
- Consumes: domain models, GRDB `DatabaseQueue`.
- Produces: `DramaDatabase.open(at: URL) throws -> DatabaseQueue` and `DramaDatabase.openInMemory() throws -> DatabaseQueue` running `CREATE TABLE` for `projects`, `episodes`, `storyboards`, `characters` with Android v12 columns (see spec). `userVersion = 12`.

`DramaRepository` methods (all throwing, run on GRDB queue):

```swift
public init(db: DatabaseQueue, filesRoot: URL)
func createProject(_ project: DramaProject) throws -> Int64
func getProjects() throws -> [DramaProject] // updated_at DESC
func getProject(_ id: Int64) throws -> DramaProject?
func updateProjectTextResult(projectId: Int64, status: ProjectStatus, currentStage: GenerationStage, generatedScript: String?, errorMessage: String?) throws
func updateProjectFinalVideo(projectId: Int64, status: ProjectStatus, currentStage: GenerationStage, finalVideoStatus: AssetStatus, finalVideoLocalPath: String?, finalVideoErrorMessage: String?, errorMessage: String?) throws
func failProcessingProjects(message: String) throws -> Int
func createEpisodeForProject(projectId: Int64, title: String, content: String?) throws -> Int64
func getEpisodeById(_ id: Int64) throws -> Episode?
func getEpisodeForProject(_ projectId: Int64) throws -> Episode? // lowest episode_number
func getEpisodes(_ projectId: Int64) throws -> [Episode]
func updateEpisodeScriptContent(episodeId: Int64, scriptContent: String?, status: EpisodeStatus) throws
func updateEpisodeFinalVideo(episodeId: Int64, finalVideoStatus: AssetStatus, finalVideoLocalPath: String?, finalVideoErrorMessage: String?) throws
func replaceStoryboards(projectId: Int64, episodeId: Int64, shots: [StoryboardShot]) throws
func getStoryboards(projectId: Int64, episodeId: Int64) throws -> [StoryboardShot]
func updateShotImage(shotId: Int64, imageStatus: AssetStatus, imageUrl: String?, imageLocalPath: String?, imageErrorMessage: String?) throws
func updateShotVideo(shotId: Int64, videoStatus: AssetStatus, videoTaskId: String?, videoUrl: String?, videoLocalPath: String?, videoErrorMessage: String?) throws
func updateShotImagePrompt(shotId: Int64, newPrompt: String) throws
func updateShotVideoPrompt(shotId: Int64, newPrompt: String) throws
func deleteProject(_ projectId: Int64) throws -> Bool // delete storyboards, characters, episodes, project, and generated/<id>/ directory
```

SQL column names must match the spec exactly (`episode_title`, `episode_status`, etc.).

- [ ] **Step 1: Write failing repository tests against `openInMemory()`**

1. `createProject` then `getProjects` returns it.
2. `createEpisodeForProject` inserts episode 1; second call inserts episode 2 (needed for schema even without UI).
3. `replaceStoryboards` deletes previous rows for that episode only.
4. `failProcessingProjects` flips `PROCESSING` → `FAILED` with message `生成任务中断（应用被关闭），请重新开始`.
5. `deleteProject` removes rows.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter DramaRepositoryTests`

Expected: FAIL.

- [ ] **Step 3: Implement database + data sources + repository. Copy CREATE TABLE strings from Android `DramaLocalDatabase` companion SQL.**

Map rows with `ProjectStatus(persisted:)`. JSON for `character_names` stored as text array string (e.g. `["A"]`); read with JSONDecoder.

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter DramaRepositoryTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Local ZdramaIOS/Tests/ZdramaCoreTests/DramaRepositoryTests.swift
git commit -m "feat(ios): add zdrama.db schema and DramaRepository"
```

---

### Task 9: CreateDramaUseCase

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/CreateDramaUseCase.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/CreateDramaUseCaseTests.swift`

**Interfaces:**
- Consumes: `DramaRepository.createProject`, `createEpisodeForProject`.
- Produces: `CreateDramaUseCase.execute(_ input: CreateDramaInput) throws -> Int64`. Inserts `DramaProject` with `id=0`, `status=draft`, `currentStage=none`, `finalVideoStatus=pending`, timestamps `Int64(Date().timeIntervalSince1970 * 1000)`. Then `createEpisodeForProject(projectId:title:content:)` with `title = input.title`, `content = input.prompt`.

- [ ] **Step 1: Write failing test** — create with title `T` prompt `P`; assert project row and episode 1 content `P`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter CreateDramaUseCaseTests`

Expected: FAIL.

- [ ] **Step 3: Implement use case mirroring Android `CreateDramaUseCase.kt`.**

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter CreateDramaUseCaseTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/CreateDramaUseCase.swift ZdramaIOS/Tests/ZdramaCoreTests/CreateDramaUseCaseTests.swift
git commit -m "feat(ios): create project and episode 1"
```

---

### Task 10: Agnes HTTP client and remote repositories

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesHTTPClient.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesEndpoints.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesTextRepository.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesStoryboardRepository.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesImageRepository.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesVideoRepository.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Data/Media/MediaDownloadRepository.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/AgnesRemoteRepositoryTests.swift`

**Interfaces:**
- Consumes: `AgnesSettings`, extractors, parsers, `VideoFrameCalculator`, `PromptDefaults`, `PromptResolver`.
- Produces:

```swift
public protocol AgnesHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAgnesHTTPClient: AgnesHTTPClient {
    public init(timeoutSeconds: Int)
}

public enum AgnesEndpoints {
    public static func chatCompletions(baseURL: String) -> URL
    public static func imagesGenerations(baseURL: String) -> URL
    public static func videos(baseURL: String) -> URL
    public static func video(baseURL: String, taskId: String) -> URL
    // v1/chat/completions, v1/images/generations, v1/videos, v1/videos/{id}
}

public struct VideoGenerationResult: Equatable, Sendable {
    public var taskId: String?
    public var videoUrl: String
}

public struct AgnesTextRepository: Sendable {
    public init(client: AgnesHTTPClient)
    public func generateScript(settings: AgnesSettings, project: DramaProject, storyPrompt: String) async throws -> String
    public func rewriteScript(settings: AgnesSettings, rawContent: String) async throws -> String
    public func ping(settings: AgnesSettings) async throws
}

public struct AgnesStoryboardRepository: Sendable {
    public init(client: AgnesHTTPClient)
    public func generateStoryboards(settings: AgnesSettings, project: DramaProject, script: String) async throws -> [StoryboardShot]
}

public struct AgnesImageRepository: Sendable {
    public init(client: AgnesHTTPClient)
    public func generateImage(settings: AgnesSettings, prompt: String) async throws -> String
}

public struct AgnesVideoRepository: Sendable {
    public init(client: AgnesHTTPClient, sleep: @escaping (UInt64) async -> Void)
    public func generateVideo(settings: AgnesSettings, shot: StoryboardShot, imageReference: String?) async throws -> VideoGenerationResult
}

public struct MediaDownloadRepository: Sendable {
    public init(client: AgnesHTTPClient, paths: GeneratedMediaPaths)
    public func downloadShotImage(projectId: Int64, shotId: Int64, url: String) async throws -> String
    public func downloadShotVideo(projectId: Int64, shotId: Int64, url: String) async throws -> String
    public func deleteGeneratedMedia(projectId: Int64) throws
}
```

Request rules:
- Header `Authorization: Bearer <apiKey>`, `Content-Type: application/json`.
- Blank apiKey / textModel / imageModel / videoModel throw `Agnes API Key is required` / `Text model is required` / `Image model is required` / `Video model is required` before send.
- Script: temperature 0.7, max_tokens 4000, system = create prompt, user = Android `buildUserPrompt` Chinese template (标题/提示词/风格/受众/画幅/镜头数量/单镜头时长). Extract via `extract`. Empty → `Agnes 未返回脚本文本，请检查文本模型是否支持 chat/completions`.
- Rewrite: 0.7 / 6000, user `请将以下内容改写为格式化短剧剧本。\n\n【原始内容】\n{raw}`. Empty → `Agnes 未返回改写内容，请检查文本模型是否支持 chat/completions`.
- Ping: user `ping`, temperature 0, max_tokens 8.
- Storyboard: 0.3 / 10000, `extractFinalContent`. Blank + `finish_reason=length` → `分镜生成被模型截断，请减少分镜数量或换用支持更长输出的文本模型`. Empty items → `Agnes 未返回分镜内容`. User prompt matches Android `buildUserPrompt` (English project fields + scene-header hint vs `Expected shot count`). Map items to `StoryboardShot` with `id=0`, `characterIds` = JSON of names if non-empty, asset statuses pending.
- Image body: `{model, prompt, size:"1024x768", n:1, extra_body:{response_format:"url"}}` (omit `image`). URL from `data[0].url` or top-level `url`.
- Video body keys: `model`, `prompt`, `num_frames`, `frame_rate`, `width`, `height`, `image`, `mode`. Prompt = join non-blank `videoPrompt`/`action`/`camera` with `。` plus `。请使用中文对白与中文旁白。`. Immediate complete if `status==completed` and URL in `metadata.url` / `video_url` / `url` / `remixed_from_video_id`. Else poll `GET v1/videos/{taskId}` 60 times; `sleep` injected for tests (production: 10_000_000_000 ns). `failed` uses `error.message` or `Video generation failed`. After 60: `Video generation timed out`. Missing image → `Generate image before video`.
- Downloads: dedicated `URLSession` (or the injected client) without the Authorization header; timeout 120s; write to path helper; HTTP non-2xx → `Media download failed: HTTP {code}`.

- [ ] **Step 1: Write a `FakeAgnesHTTPClient` in the test file that records `URLRequest`s and returns queued `(Data, status)`.** Cover: script extracts content; missing text model does not send; storyboard parses array; image URL; video polls twice then completed; video timeout after 60 empty processing responses with sleep no-op.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter AgnesRemoteRepositoryTests`

Expected: FAIL.

- [ ] **Step 3: Implement client and repositories. Join URLs with `AgnesSettingsStore.normalizeBaseURL`.**

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter AgnesRemoteRepositoryTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Remote ZdramaIOS/Sources/ZdramaCore/Data/Media/MediaDownloadRepository.swift ZdramaIOS/Tests/ZdramaCoreTests/AgnesRemoteRepositoryTests.swift
git commit -m "feat(ios): add Agnes text, image, video, and download clients"
```

---

### Task 11: Script, rewrite, and storyboard use cases

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateProjectScriptUseCase.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/RewriteEpisodeScriptUseCase.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateStoryboardsUseCase.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/ScriptUseCaseTests.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/StoryboardUseCaseTests.swift`

**Interfaces:**
- Consumes: `DramaRepository`, `AgnesTextRepository`, `AgnesStoryboardRepository`.
- Produces:

```swift
public struct GenerateProjectScriptUseCase {
    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> String
}
public struct RewriteEpisodeScriptUseCase {
    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> String
}
public struct GenerateStoryboardsUseCase {
    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> [StoryboardShot]
}
```

Behavior copy Android:
- Script: mark project PROCESSING/TEXT; storyPrompt = episode.content if non-blank else project.prompt; on success write episode script COMPLETED and project generatedScript; on failure episode FAILED, keep previous script, project FAILED + message.
- Rewrite: require non-blank content; episode REWRITING then COMPLETED/FAILED; stage TEXT.
- Storyboard: require this episode `scriptContent` (never fall back to `project.generatedScript`); PROCESSING/STORYBOARD; replaceStoryboards on success with `episodeId` set on each shot.

- [ ] **Step 1: Write failing tests with Fake HTTP client + in-memory DB.** Script uses episode content not project prompt. Storyboard with only `project.generatedScript` set fails `请先为本集创作或改写脚本`. Rewrite empty content fails without HTTP.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ZdramaIOS && swift test --filter ScriptUseCaseTests --filter StoryboardUseCaseTests`

Expected: FAIL.

- [ ] **Step 3: Implement the three use cases.**

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter ScriptUseCaseTests --filter StoryboardUseCaseTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateProjectScriptUseCase.swift \
  ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/RewriteEpisodeScriptUseCase.swift \
  ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateStoryboardsUseCase.swift \
  ZdramaIOS/Tests/ZdramaCoreTests/ScriptUseCaseTests.swift \
  ZdramaIOS/Tests/ZdramaCoreTests/StoryboardUseCaseTests.swift
git commit -m "feat(ios): add script rewrite and storyboard use cases"
```

---

### Task 12: Image, video, and compose use cases

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateStoryboardImagesUseCase.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateStoryboardVideosUseCase.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/ComposeFinalVideoUseCase.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/ImageVideoUseCaseTests.swift`

**Interfaces:**
- Consumes: repositories, `LocalMp4Composer`, `GeneratedMediaPaths`.
- Produces:

```swift
public struct GenerateStoryboardImagesUseCase {
    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws
}
public struct GenerateStoryboardVideosUseCase {
    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws
}
public struct ComposeFinalVideoUseCase {
    public init(dramaRepository: DramaRepository, composer: LocalMp4Composer, paths: GeneratedMediaPaths)
    public func execute(projectId: Int64, episodeId: Int64) async throws -> String
}
```

Images: skip when `imageStatus==completed` and local file exists; else PROCESSING, generate, download, COMPLETED. On first failure mark that shot FAILED, project FAILED, throw; do not continue remaining shots. All skip or all success → project COMPLETED / IMAGE.

Videos: skip completed local files; `imageReference` = data URI of local image (`data:image/jpeg;base64,...` / png / webp by extension) else `shot.imageUrl`. Same fail-fast as images. Stage VIDEO.

Data URI helper: read file, base64, mime from extension.

Compose: empty shots → `请先生成分镜`; any shot not completed local video → `请先生成并下载全部分镜视频后再合成成片`; PROCESSING/FINAL_VIDEO; output `paths.finalVideo`; success writes episode + project final video COMPLETED; failure markFailed (project FAILED, episode final FAILED, path nil).

- [ ] **Step 1: Write failing tests**
  - Two shots, first already completed with a temp file, second generates once (assert one image POST).
  - Second image HTTP 500: first stays completed, second FAILED, execute throws, third shot (if any) not requested — use two shots only.
  - Compose with empty storyboards throws 请先生成分镜.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter ImageVideoUseCaseTests`

Expected: FAIL.

- [ ] **Step 3: Implement use cases. For compose tests, inject a `LocalMp4Composer` subclass or make `compose` a closure in tests via a `Mp4Composing` protocol:**

```swift
public protocol Mp4Composing: Sendable {
    func compose(inputPaths: [String], outputPath: String) async throws -> String
}
extension LocalMp4Composer: Mp4Composing {}
```

Test composer writes a tiny file at `outputPath` and returns it.

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter ImageVideoUseCaseTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateStoryboardImagesUseCase.swift \
  ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateStoryboardVideosUseCase.swift \
  ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/ComposeFinalVideoUseCase.swift \
  ZdramaIOS/Tests/ZdramaCoreTests/ImageVideoUseCaseTests.swift
git commit -m "feat(ios): add image, video, and final compose use cases"
```

---

### Task 13: GenerationCoordinator

**Files:**
- Create: `ZdramaIOS/Sources/ZdramaCore/Generation/GenerationCoordinator.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/GenerationCoordinatorTests.swift`

**Interfaces:**
- Consumes: all generation use cases, `AgnesSettingsStore`. Preflight in Task 5 already uses these stage strings.
- Produces:

```swift
public enum GenerationStageKey {
    public static let text = "text"
    public static let rewrite = "rewrite"
    public static let storyboard = "storyboard"
    public static let image = "image"
    public static let video = "video"
    public static let finalVideo = "final_video"
    public static let full = "full"
}

public actor GenerationCoordinator {
    public init(/* use case deps + settingsStore */)
    public func isRunning(projectId: Int64, episodeId: Int64) -> Bool
    public func enqueue(projectId: Int64, episodeId: Int64, stage: String, forceRegenerate: Bool) async
    public func cancel(projectId: Int64, episodeId: Int64) async
}
```

Unique key `"generation-{projectId}-{episodeId}-{stage}"`. If running and `forceRegenerate == false`, return (KEEP). If `forceRegenerate`, cancel that key then start (REPLACE). `full` runs text → storyboard → image → video → final_video, stop on throw. Cancel: cancel running `Task`s for that episode, set project `CANCELLED` (do not overwrite with FAILED). CancellationError must not mark FAILED.

- [ ] **Step 1: Write failing tests with a fake text repository that waits on a continuation.** Double enqueue of `text` starts once. `forceRegenerate` starts a second task after cancelling. `full` stops if script throws (no storyboard HTTP). Cancel mid-wait leaves status CANCELLED.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter GenerationCoordinatorTests`

Expected: FAIL.

- [ ] **Step 3: Implement the actor. Load settings at start of each job. Unknown stage fails the job.**

- [ ] **Step 4: Run tests**

Run: `cd ZdramaIOS && swift test --filter GenerationCoordinatorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Generation/GenerationCoordinator.swift ZdramaIOS/Tests/ZdramaCoreTests/GenerationCoordinatorTests.swift
git commit -m "feat(ios): add in-process generation coordinator"
```

---

### Task 14: iOS app shell — home, settings, create, list

**Files:**
- Create: `ZdramaIOS/App/ZdramaApp.swift`
- Create: `ZdramaIOS/App/AppContainer.swift`
- Create: `ZdramaIOS/App/RootView.swift`
- Create: `ZdramaIOS/App/Features/Home/HomeView.swift`
- Create: `ZdramaIOS/App/Features/Settings/SettingsView.swift`
- Create: `ZdramaIOS/App/Features/Settings/ManagePromptsView.swift`
- Create: `ZdramaIOS/App/Features/Create/CreateProjectView.swift`
- Create: `ZdramaIOS/App/Features/ProjectList/ProjectListView.swift`
- Create: `ZdramaIOS/project.yml`
- Modify: `.gitignore` if XcodeGen output needs exceptions — commit `ZdramaIOS.xcodeproj` if generated.

**Interfaces:**
- Consumes: `CreateDramaUseCase`, `AgnesSettingsStore`, `AgnesTextRepository.ping`, `DramaRepository`.
- Produces: SwiftUI navigation. `AppContainer` builds a single `DatabaseQueue` at `Application Support/zdrama.db`, `GeneratedMediaPaths(root: Documents or Application Support)`, settings store, coordinator, use cases.

UI copy:
- Home buttons: 设置, 新建, 项目.
- Create defaults: style `现代短剧`, audience `大众受众`, aspect `9:16`. Title and prompt required; shotCount and duration > 0. Save → create → push detail (detail stub `Text("detail \(id)")` until Task 15).
- Settings: API Key (secure field), Base URL, 文本模型, 图片模型, 视频模型, 保存, 测试文本连通, 提示词.
- Prompts: three tabs 创作 / 改写 / 分镜; 保存 / 恢复默认; leaving a dirty tab confirms.
- List: `updatedAt` desc; swipe delete confirms; delete calls `coordinator.cancel` then `deleteProject`.

- [ ] **Step 1: Add `project.yml` for XcodeGen**

```yaml
name: Zdrama
options:
  bundleIdPrefix: com.huobao
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    PRODUCT_NAME: 火宝短剧
    SWIFT_VERSION: "5.9"
packages:
  ZdramaCore:
    path: .
targets:
  Zdrama:
    type: application
    platform: iOS
    sources:
      - App
    dependencies:
      - package: ZdramaCore
        product: ZdramaCore
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: 火宝短剧
        CFBundleIdentifier: com.huobao.zdrama
        UILaunchScreen: {}
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
```

If XcodeGen is missing, write an equivalent `ZdramaIOS/Zdrama.xcodeproj` by running `xcodegen generate --spec project.yml` when the binary exists; otherwise create the iOS app as a second SPM-unfriendly target documented in README snippet at top of `ZdramaIOS/App/ZdramaApp.swift` comments: open Package.swift in Xcode, File → New → Project iOS App, add local package. Prefer generating the xcodeproj so the spec path `ZdramaIOS/` is openable.

`ZdramaApp`:

```swift
import SwiftUI
import ZdramaCore

@main
struct ZdramaApp: App {
    @State private var container = AppContainer.bootstrap()
    var body: some Scene {
        WindowGroup { RootView(container: container) }
    }
}
```

On bootstrap: `try dramaRepository.failProcessingProjects(message: "生成任务中断（应用被关闭），请重新开始")`.

- [ ] **Step 2: Implement views listed above. Keep each view under ~200 lines.** Create form validation errors in Chinese.

- [ ] **Step 3: Generate xcodeproj if possible**

Run: `which xcodegen && (cd ZdramaIOS && xcodegen generate)`

If `xcodegen` / `xcodebuild` missing, record stdout/stderr in the commit message body, still commit sources.

- [ ] **Step 4: Compile if Xcode exists**

Run: `cd ZdramaIOS && xcodebuild -scheme Zdrama -destination 'generic/platform=iOS' build`

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/App ZdramaIOS/project.yml ZdramaIOS/Zdrama.xcodeproj
git commit -m "feat(ios): add SwiftUI home, settings, create, and project list"
```

---

### Task 15: Detail, viewers, player

**Files:**
- Create: `ZdramaIOS/App/Features/ProjectDetail/ProjectDetailView.swift`
- Create: `ZdramaIOS/App/Features/ProjectDetail/ProjectDetailViewModel.swift`
- Create: `ZdramaIOS/App/Features/ProjectDetail/GenerationProgressCard.swift`
- Create: `ZdramaIOS/App/Features/ProjectDetail/GenerationActionsView.swift`
- Create: `ZdramaIOS/App/Features/Script/ScriptViewerView.swift`
- Create: `ZdramaIOS/App/Features/Storyboard/StoryboardViewerView.swift`
- Create: `ZdramaIOS/App/Features/Gallery/ImageGalleryView.swift`
- Create: `ZdramaIOS/App/Features/Player/VideoPlayerView.swift`

**Interfaces:**
- Consumes: `GenerationPreflight`, `GenerationCoordinator`, `DramaRepository`.
- Produces: detail screen with buttons 全部生成 / 剧本 / 改写 / 分镜 / 出图 / 出视频 / 成片 / 取消; links 查看剧本 / 分镜 / 图库 / 镜头视频 / 成片. While `isRunning`, disable generation buttons. Timer 1.5s reloads project + shots. Progress: `completed/total` for IMAGE/VIDEO and the PROCESSING shot number. Status line uses Chinese stage names: 剧本 / 分镜 / 出图 / 出视频 / 成片.

Overwrite confirm when target already exists (non-blank script / any shots / any completed image / video / final). Cancel calls `coordinator.cancel`. Delete project as in list.

Script viewer: read-only `episode.scriptContent`.
Storyboard: cards with editable image/video prompts calling `updateShotImagePrompt` / `updateShotVideoPrompt`.
Gallery: grid of local image else AsyncImage URL. Read-only.
Player: `mode: shots | final`. Shots: previous/next, `VideoPlayer` with local file URL else remote URL. Final: episode `finalVideoLocalPath`.

ViewModel preflight maps `PreflightError` to `alertMessage`. Do not enqueue on preflight failure.

- [ ] **Step 1: Implement ViewModel with a test in core if logic is extracted:** `ProjectDetailViewModel.shouldConfirmOverwrite(stage:project:episode:shots:) -> Bool`. Add `ZdramaIOS/Tests/ZdramaCoreTests/ProjectDetailLogicTests.swift` for overwrite + display stage names to avoid stuffing logic in the SwiftUI file.

Overwrite true when:
- text/rewrite/full: scriptContent non-blank
- storyboard: shots non-empty
- image: any completed image
- video: any completed video
- final_video: episode finalVideoStatus completed with file

- [ ] **Step 2: Run `swift test --filter ProjectDetailLogicTests`**

Expected: PASS after implementation.

- [ ] **Step 3: Build SwiftUI screens. Split actions vs progress vs header. No character buttons, no episode chips, no API log.**

- [ ] **Step 4: Commit**

```bash
git add ZdramaIOS/App/Features ZdramaIOS/Tests/ZdramaCoreTests/ProjectDetailLogicTests.swift
git commit -m "feat(ios): add project detail, viewers, and players"
```

---

### Task 16: Wire Info.plist, assets, and verify

**Files:**
- Create: `ZdramaIOS/App/Assets.xcassets/AppIcon.appiconset/Contents.json` (empty placeholder is fine)
- Create: `ZdramaIOS/App/Info.plist` if not already from Task 14
- Modify: `docs/superpowers/specs/2026-09-29-ios-zdrama-native-design.md` only if a discovered mismatch must be recorded — prefer not changing the spec.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: `swift test` green; xcodebuild when available.

- [ ] **Step 1: Run the full core suite**

Run: `cd ZdramaIOS && swift test`

Expected: all tests PASS.

- [ ] **Step 2: Try xcodebuild**

Run: `cd ZdramaIOS && xcodebuild -scheme Zdrama -destination 'generic/platform=iOS' build`

If Xcode missing, paste the exact error into the final commit message / a short `ZdramaIOS/README.md`:

```markdown
# Zdrama iOS

SwiftUI client. Logic: `swift test` in this directory.

Open `Zdrama.xcodeproj` (generate with `xcodegen generate` if needed).
```

- [ ] **Step 3: Manual checklist (do not claim e2e Agnes success without credentials)**
  - Create project locally
  - Settings save/load
  - Preflight alert without API key

- [ ] **Step 4: Commit**

```bash
git add ZdramaIOS
git commit -m "feat(ios): verify ZdramaCore tests and document iOS build"
```

---

## Execution notes

Copy Android files instead of inventing prompts, SQL, and Agnes JSON keys:

- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/prompt/PromptDefaults.kt`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/local/DramaLocalDatabase.kt`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/remote/ChatResponseTextExtractor.kt`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/repository/AgnesStoryboardRepository.kt`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/repository/AgnesVideoRepository.kt`

Do not implement character extract, album save, or multi-episode UI even if those Android files are nearby.
