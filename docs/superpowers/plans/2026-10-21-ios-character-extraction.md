# iOS Character Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Android-aligned character extraction, character portraits, and a character list to the Swift iOS app.

**Architecture:** Persist characters through the existing `characters` table, call Agnes chat/image the same way script and shot images already do, and run both jobs on `GenerationCoordinator`. The detail screen enqueues them; a new list screen shows the rows.

**Tech Stack:** Swift, SwiftUI, GRDB, XCTest, existing `AgnesHTTPClient` and `MediaDownloadRepository`.

**Spec:** `docs/superpowers/specs/2026-10-21-ios-character-extraction-design.md`

## Global Constraints

- Swift app `ZdramaIOS/` only. Do not modify `ZdramaIOSObjC/`.
- Characters belong to the project. Same-name upsert updates text and keeps the portrait; characters absent from this extraction are not deleted.
- Blank current-episode script fails with `请先为本集创作或改写脚本`. Do not fall back to the project script.
- Batch portraits use job key `generation-<projectId>-character_image`. Confirmed overwrite passes `forceRegenerate: true` into the use case.
- A single redraw uses key `character_image_<characterId>` and always regenerates.
- Portrait file is `generated/<projectId>/char_<characterId>_image.<ext>`.
- Do not inject character images into storyboard generation, and do not add characters to the `full` stage.
- Copy for confirmations and empty states is the Android copy named in the spec.

## Review Focus

- A chat reply that wraps the JSON array in prose still extracts the array.
- A same-name character keeps its completed portrait after extraction.
- Batch generation with `forceRegenerate: false` skips a completed portrait whose file exists, then continues after a later failure.
- Confirming overwrite reaches the use case as `forceRegenerate: true`; the flag is not dropped at the queue.
- Cancelling the episode also cancels the project-level character-image job.
- While that project-level job is running, the detail screen treats the episode as busy (`isRunning` matches it), so generate buttons stay disabled.

---

### Task 1: Character persistence

**Files:**
- Modify: `ZdramaIOS/Sources/ZdramaCore/Data/Local/CharacterLocalDataSource.swift`
- Modify: `ZdramaIOS/Sources/ZdramaCore/Data/Local/DramaRepository.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/DramaRepositoryTests.swift`

**Interfaces:**
- Consumes: existing `Character` in `DramaModels.swift` and `characters` table in `DramaDatabase.swift`.
- Produces:
  - `DramaRepository.getCharacters(projectId: Int64) throws -> [Character]` ordered by id ascending.
  - `DramaRepository.upsertCharacters(projectId: Int64, characters: [Character]) throws`. `id > 0` updates only `role`, `description`, `appearance`, `personality`, `updated_at`. `id == 0` inserts. Neither deletes other rows.
  - `DramaRepository.updateCharacterImage(characterId: Int64, status: AssetStatus, url: String?, localPath: String?, errorMessage: String?) throws`.

- [ ] **Step 1: Write the failing test**

Add `testUpsertCharactersKeepsPortraitAndUntouchedRows` to `DramaRepositoryTests`. Insert one character through `upsertCharacters` with `id: 0`, image status `.completed`, and a local path. Upsert again with that returned id, a new appearance, and a second new character (`id: 0`). Assert the first row keeps its id, image status, and local path, the appearance changed, and a third pre-existing character that was not in the second upsert is still present. Then call `updateCharacterImage` and assert status `.failed` and the error string.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter DramaRepositoryTests/testUpsertCharactersKeepsPortraitAndUntouchedRows`
Expected: FAIL because `upsertCharacters` is not defined.

- [ ] **Step 3: Implement the three repository methods**

SQL lives in `CharacterLocalDataSource`; `DramaRepository` forwards. Insert uses the `Character` values except `projectId` from the argument and `createdAt`/`updatedAt` from `LocalClock.nowMillis()` when inserting. Update text does not touch image columns or `episode_id`.

- [ ] **Step 4: Run test to verify it passes**

Run the same filter. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Local/CharacterLocalDataSource.swift ZdramaIOS/Sources/ZdramaCore/Data/Local/DramaRepository.swift ZdramaIOS/Tests/ZdramaCoreTests/DramaRepositoryTests.swift
git commit -m "feat(ios): persist extracted characters"
```

### Task 2: Extract characters

**Files:**
- Modify: `ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesTextRepository.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/ExtractCharactersUseCase.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/ExtractCharactersUseCaseTests.swift`

**Interfaces:**
- Consumes: Task 1 repository methods; `PromptResolver.resolve`; `PromptDefaults.characterExtractPrompt`; `ChatResponseTextExtractor`.
- Produces:
  - `AgnesTextRepository.complete(settings: AgnesSettings, messages: [[String: String]], temperature: Double, maxTokens: Int) async throws -> String` — public wrapper over the private `postChat`, returning the extracted assistant text.
  - `ExtractCharactersUseCase.execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> Int`.

- [ ] **Step 1: Write the failing tests**

Use the stub URL protocol pattern already used by `AgnesRemoteRepositoryTests` / script use case tests. Three tests:

- `testExtractRequiresEpisodeScript`: blank `scriptContent` throws `请先为本集创作或改写脚本` and records no request.
- `testExtractMergesSameNameAndKeepsPortrait`: existing character "沈惊川" is `.completed` with a local path. The stub returns a chat body whose content is prose plus a JSON array containing that name with a new appearance and a new name. Assert the old id and portrait remain, appearance updates, and the new name is inserted. Assert the request body contains `0.3` and `4000`.
- `testExtractRejectsUnparseableReply`: content with no `[...]` throws `无法解析角色提取结果`.

User prompt text matches the Android string in the spec, including the existing-name sentence joined by `、` and the `existing_id` instruction only when characters already exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter ExtractCharactersUseCaseTests`
Expected: FAIL to compile, type not found.

- [ ] **Step 3: Implement extraction**

`complete` calls `postChat` and `ChatResponseTextExtractor`. The use case loads the episode script only, builds the two messages, parses the first `[` through the last `]`, matches existing rows by trimmed name, and calls `upsertCharacters`. Empty names are dropped. A blank field keeps the existing value. Missing project or episode throws `Project not found` / `Episode not found`. An empty parsed list throws `未从剧本中提取到角色`.

- [ ] **Step 4: Run test to verify it passes**

Same filter. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Remote/AgnesTextRepository.swift ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/ExtractCharactersUseCase.swift ZdramaIOS/Tests/ZdramaCoreTests/ExtractCharactersUseCaseTests.swift
git commit -m "feat(ios): extract characters from the episode script"
```

### Task 3: Character portraits

**Files:**
- Modify: `ZdramaIOS/Sources/ZdramaCore/Data/Media/GeneratedMediaPaths.swift`
- Modify: `ZdramaIOS/Sources/ZdramaCore/Data/Media/MediaDownloadRepository.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateCharacterImagesUseCase.swift`
- Create: `ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateSingleCharacterImageUseCase.swift`
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/GenerateCharacterImagesUseCaseTests.swift`

**Interfaces:**
- Consumes: Task 1 image update; `AgnesImageRepository.generateImage(settings:prompt:)`.
- Produces:
  - `GeneratedMediaPaths.characterImage(projectId: Int64, characterId: Int64, ext: String) -> URL`.
  - `MediaDownloadRepository.downloadCharacterImage(projectId: Int64, characterId: Int64, url: String) async throws -> String`.
  - `GenerateCharacterImagesUseCase.execute(projectId:episodeId:settings:forceRegenerate:) async throws -> Int`. `episodeId` is accepted so the coordinator call shape matches other stages; it is not used to filter characters.
  - `GenerateSingleCharacterImageUseCase.execute(projectId:characterId:settings:forceRegenerate:) async throws -> String` with default `forceRegenerate: true`.
  - Prompt: `"<name>, <appearance or description or character portrait>, high quality, front-facing portrait"`.

- [ ] **Step 1: Write the failing tests**

- `testBatchSkipsCompletedFileAndContinuesAfterFailure`: two characters. First is `.completed` and its local file exists; second generation returns HTTP 500. With `forceRegenerate: false`, exactly one image request is made, the first row stays `.completed`, the second becomes `.failed`, and the error is thrown only because nothing new was generated.
- `testBatchForceRegenerateRedrawsCompletedFile`: the same completed file is requested again when `forceRegenerate: true`.
- `testBatchRequiresCharacters`: no rows throws `请先提取角色`.
- `testSingleRedrawMarksFailed`: missing URL marks that character `.failed` and throws.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter GenerateCharacterImagesUseCaseTests`
Expected: FAIL to compile.

- [ ] **Step 3: Implement both use cases and the download path**

Follow `GenerateStoryboardImagesUseCase` for status transitions. Batch: skip when `!forceRegenerate && status == .completed && file exists`; on failure mark `.failed` and continue; return the count of newly generated images when that count is positive or every character succeeded (including skips); otherwise throw the first error. Single: default force, throw on that character's failure. Download writes `characterImage(...)`.

- [ ] **Step 4: Run test to verify it passes**

Same filter. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Data/Media/GeneratedMediaPaths.swift ZdramaIOS/Sources/ZdramaCore/Data/Media/MediaDownloadRepository.swift ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateCharacterImagesUseCase.swift ZdramaIOS/Sources/ZdramaCore/Domain/UseCases/GenerateSingleCharacterImageUseCase.swift ZdramaIOS/Tests/ZdramaCoreTests/GenerateCharacterImagesUseCaseTests.swift
git commit -m "feat(ios): generate and download character portraits"
```

### Task 4: Queue the two stages

**Files:**
- Modify: `ZdramaIOS/Sources/ZdramaCore/Generation/GenerationCoordinator.swift`
- Modify: `ZdramaIOS/App/AppContainer.swift` (construct the two use cases and pass them in)
- Test: `ZdramaIOS/Tests/ZdramaCoreTests/GenerationCoordinatorTests.swift`

**Interfaces:**
- Consumes: Tasks 2 and 3 use cases.
- Produces: `GenerationStageKey.characterExtract = "character_extract"`, `GenerationStageKey.characterImage = "character_image"`. `enqueue` passes `forceRegenerate` into `run` for `character_image` only; other stages ignore it as they do today. Batch image job key is `generation-<projectId>-character_image` (no episode id). A stage with prefix `character_image_` runs the single use case for that id and does not use the batch key. `cancel(projectId:episodeId:)` also cancels the project batch key. `isRunning(projectId:episodeId:)` is true when that batch key is running for the same project, so the detail screen disables generation while portraits are in flight.

- [ ] **Step 1: Write the failing tests**

- `testCharacterExtractStageCallsUseCase`: enqueue `character_extract` against a stubbed chat success and assert one character row exists.
- `testCharacterImageForceRegenerateIsForwarded`: a completed portrait with a file is redrawn when enqueue is called with `forceRegenerate: true`, and is not redrawn when called with `false`.
- `testCancelStopsProjectCharacterImageJob`: start `character_image`, cancel that episode, and assert the job is no longer running. Before cancel, `isRunning(projectId:episodeId:)` for that episode is true even though the job key has no episode id.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ZdramaIOS && swift test --filter GenerationCoordinatorTests/testCharacterExtractStageCallsUseCase`
Expected: FAIL, stage is unknown or no character row.

- [ ] **Step 3: Wire the stages**

Add the keys and the two use case dependencies to the coordinator init. Thread `forceRegenerate` from `enqueue` through `runJob` into `run`; only the `character_image` case reads it. `makeJobKey` returns `generation-<projectId>-character_image` for that stage and keeps the episode-scoped form for every other stage, including `character_image_<id>`. `cancel` and `isRunning` treat a job whose key is that batch key and whose `projectId` matches as belonging to the episode. Single stage parses the id after `character_image_`. Do not add either stage to `full`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ZdramaIOS && swift test --filter 'GenerationCoordinatorTests/testCharacter'`
Expected: PASS, and the existing coordinator tests still pass.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/Sources/ZdramaCore/Generation/GenerationCoordinator.swift ZdramaIOS/App/AppContainer.swift ZdramaIOS/Tests/ZdramaCoreTests/GenerationCoordinatorTests.swift
git commit -m "feat(ios): queue character extraction and portraits"
```

### Task 5: Detail actions, list, and prompt tab

**Files:**
- Modify: `ZdramaIOS/App/Features/ProjectDetail/ProjectDetailView.swift`
- Modify: `ZdramaIOS/App/Features/ProjectDetail/ProjectDetailViewModel.swift`
- Modify: `ZdramaIOS/App/Features/Settings/ManagePromptsView.swift`
- Modify: `ZdramaIOS/App/RootView.swift`
- Create: `ZdramaIOS/App/Features/Characters/CharacterListView.swift`

**Interfaces:**
- Consumes: Task 4 stage keys and `enqueue(projectId:episodeId:stage:forceRegenerate:)`.
- Produces: detail buttons `提取角色`, `生成角色图`, `查看角色`; route `AppRoute.characters(Int64)`; prompt tab `角色提取`.

- [ ] **Step 1: Add the prompt tab**

Add a fourth `PromptTab.character` titled `角色提取`, bound to `customCharacterExtractPrompt` and `PromptDefaults.characterExtractPrompt`. Save, restore, and the dirty-tab confirmation use the existing tab machinery.

- [ ] **Step 2: Add the detail actions**

No script: alert `请先为本集创作或改写脚本` and do not enqueue. Existing characters: confirm `当前项目已有角色信息，重新提取会覆盖现有角色。是否继续？` then enqueue `character_extract`. No characters: enqueue directly.

No characters for images: alert `请先提取角色`. Any `.completed` portrait: confirm `当前项目已有角色图，重新生成会覆盖所有角色图。是否继续？` then enqueue `character_image` with `forceRegenerate: true`. Otherwise enqueue with `false`.

`查看角色` pushes `AppRoute.characters(projectId)` even when the list is empty.

- [ ] **Step 3: Add the list screen**

Title `项目角色`. Empty copy: `该项目暂无角色，请先在项目详情页提取角色`. Each row shows the local image when the file exists, otherwise the image status; name; role or `角色定位未填`; description; appearance; personality; `imageErrorMessage` when non-empty. A `生成图片` button enqueues `character_image_<id>`. Reload in `onAppear`.

- [ ] **Step 4: Build the app**

Run: `cd ZdramaIOS && xcodebuild -scheme Zdrama -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/zdrama-swift-run -quiet build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ZdramaIOS/App
git commit -m "feat(ios): show character extraction, portraits, and list"
```
