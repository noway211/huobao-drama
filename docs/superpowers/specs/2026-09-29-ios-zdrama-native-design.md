# Zdrama iOS 原生客户端设计

## Context

仓库里已有三套短剧制作实现：

- Web 全栈（Hono + Nuxt）走多厂商适配器和 Mastra Agent。
- `ZdramaAndroid/` 是独立 Android App：本地 SQLite，直连 Agnes，WorkManager 跑生成。
- `ZdramaHarmony/` 是同一产品的鸿蒙移植。

用户要求参考 Android 端做 iOS 版本，技术选型已定为 **SwiftUI 原生**。不接现有 Node 后端，不共享 Android/KMP 代码。

本设计对应第一版（能跑通单集成片）。多集、角色图、相册、单张删除、分镜绑角色参考图、API 日志页后补；表结构和模型预留这些字段，避免推倒重来。

参考实现以 Android 当前代码为准，而不是 `2026-07-07-android-agnes-mobile-drama-design.md`（那份文档仍写 Room、无本地成片，和现状不符）。

## Goal

在仓库根目录新增独立 Xcode 工程 `ZdramaIOS/`，实现与 Android 对齐的单集制作闭环：

1. 用户配置 Agnes API Key、Base URL、文本/图片/视频模型。
2. 用户创建项目（标题、创意、风格、受众、画幅、镜头数、单镜时长）。
3. App 生成格式化剧本、拆分镜、为每镜出图、为每镜出视频、无转码拼接成片。
4. 项目、分镜、媒体路径保存在本机；杀进程后未完成任务标失败，可重试。

成功标准：在配置了可用 Agnes 凭证的真机或模拟器上，一个单集项目可以从空白走到可播放的 `final_video.mp4`。本机若无 Xcode，工程文件仍须完整可打开；逻辑测试（JSON 解析、帧数公式、预检、拼接失败条件）不依赖模拟器。

## Non-Goals

第一版明确不做：

- 不调用 `huobao-drama` 的 `/api/v1`，不读 Web 的 SQLite。
- 不做多集 UI（创建时仍插入 episode 1，界面不露出选集）。
- 不做角色提取、角色列表、角色图、分镜绑角色、图生图参考图。
- 不保存到系统相册，不提供单张图片/视频/成片删除按钮（删除整个项目除外）。
- 不做 API 日志页。
- 不做 TTS、字幕、BGM、多厂商适配。
- 不上 `BGProcessingTask` / 后台续跑；杀进程即中断。
- 不引入 SwiftData、不引入 KMP、不把 Android Room 那套未使用 schema 搬过来。

## Recommended Direction

独立 SwiftUI App，分层对齐 Android 的 UseCase / Repository / SQLite，但页面拆成 View + ViewModel，避免再出现 `ProjectDetailActivity` 那种千行文件。

```text
Agnes API -> UseCase -> SQLite + 本地文件 -> ViewModel (@Observable) -> SwiftUI
后台 Task 只通过 UseCase 写库；UI 从库刷新，不依赖任务内存状态。
```

不推荐：把 iOS 做成 Web 壳（数据模型和厂商策略不同）；先抽 KMP 再写 iOS（要先重构 Android）。

## App Identity And Layout

- 工程目录：`ZdramaIOS/`
- Bundle ID：`com.huobao.zdrama`
- 显示名：火宝短剧
- 最低系统：iOS 17
- UI：SwiftUI，无 UIKit 页面（播放器用 `AVPlayer` / `VideoPlayer`）
- 不把 iOS 工程并入根 `package.json`

目录：

```text
ZdramaIOS/
  App/                      ZdramaApp, AppDelegate-equivalent 冷启动修复
  Domain/Models/            DramaModels
  Domain/UseCases/          每个生成步骤一个类型
  Data/Local/               SQLite (zdrama.db) + DataSources + DramaRepository
  Data/Remote/              Agnes client, DTO, chat/image/video repos, text extractor
  Data/Settings/            Keychain + UserDefaults
  Data/Prompt/              PromptDefaults, PromptResolver
  Data/Media/               download, path helper, AVFoundation composer
  Features/Home/
  Features/Create/
  Features/ProjectList/
  Features/ProjectDetail/   详情拆成多个小组件，不把预检/导航/进度写进一个 View
  Features/Script/
  Features/Storyboard/
  Features/Gallery/
  Features/Player/
  Features/Settings/
  Generation/               GenerationCoordinator（串行任务 + 取消）
```

依赖规则：

- Features 只调 UseCase 和只读仓库查询（列表/详情刷新），不直接发 HTTP、不直接拼 SQL。
- UseCase 调仓库。
- Remote 只负责 Agnes 协议和解析，不写库。
- 本地文件路径由媒体层统一给出。

SQLite 用 `GRDB.swift`（SPM）。不用手写全套 sqlite3 绑定，也不用 SwiftData。

## Domain Model

枚举名与 Android 一致，持久化为枚举 `name` 字符串。未知值回退：`ProjectStatus` → `DRAFT`，`GenerationStage` → `NONE`，`AssetStatus` → `PENDING`，`EpisodeStatus` → `DRAFT`。

```text
ProjectStatus:     DRAFT | PROCESSING | COMPLETED | FAILED | CANCELLED
GenerationStage:   NONE | TEXT | STORYBOARD | IMAGE | VIDEO | FINAL_VIDEO
AssetStatus:       PENDING | PROCESSING | COMPLETED | FAILED
EpisodeStatus:     DRAFT | REWRITING | COMPLETED | FAILED
```

`CreateDramaInput`：`title`, `prompt`, `style`, `targetAudience`, `aspectRatio`, `shotCount`, `shotDurationSeconds`。

`DramaProject` 字段与 Android 对齐，含 `generatedScript` 和项目级 `finalVideo*` 镜像列。第一版真正读写走 episode 1 的 `scriptContent` / `finalVideoLocalPath`；写剧本成功时同时更新 `project.generatedScript`。

`Episode`：`id`, `projectId`, `episodeNumber`, `title`, `content`, `scriptContent`, `status`, `finalVideoStatus`, `finalVideoLocalPath`, `finalVideoErrorMessage`, timestamps。创建项目时插入 `episodeNumber = 1`，`title` 用项目标题，`content` 用项目 `prompt`。

`StoryboardShot` 含 `episodeId`（第一版始终为 episode 1）、`characterNames` / `characterIds`（生成时写入 LLM 返回的名字 JSON，UI 不编辑绑定）。图片/视频状态字段与 Android 相同。

`Character` 模型可定义，第一版无 UseCase、无页面读写。

## SQLite Schema

数据库文件：`Application Support/zdrama.db`。第一版直接建齐 Android v12 的四张表（含 `characters`），version = 12，无历史迁移。列名与 Android `DramaLocalDatabase` 一致：

- `projects`：`id`, `title`, `prompt`, `style`, `target_audience`, `aspect_ratio`, `shot_count`, `shot_duration_seconds`, `status`, `current_stage`, `error_message`, `generated_script`, `final_video_status`, `final_video_local_path`, `final_video_error_message`, `created_at`, `updated_at`
- `episodes`：`id`, `project_id`, `episode_number`, `episode_title`, `content`, `script_content`, `episode_status`, `final_video_status`, `final_video_local_path`, `final_video_error_message`, `created_at`, `updated_at`
- `storyboards`：`id`, `project_id`, `episode_id`, `shot_number`, `scene`, `action`, `dialogue`, `camera`, `image_prompt`, `video_prompt`, `duration_seconds`, `character_names`, `character_ids`, `image_status`, `image_url`, `image_local_path`, `image_error_message`, `video_status`, `video_task_id`, `video_url`, `video_local_path`, `video_error_message`, `created_at`, `updated_at`
- `characters`：`id`, `project_id`, `episode_id`, `name`, `role`, `description`, `appearance`, `personality`, `image_status`, `image_url`, `image_local_path`, `image_error_message`, `created_at`, `updated_at`（第一版空表，无读写）

时间戳用 epoch 毫秒 `INTEGER`，与 Android 一致。

冷启动：若存在 `status = PROCESSING` 的项目，取消进行中的 `GenerationCoordinator` 任务，将这些项目标为 `FAILED`，`error_message = 生成任务中断（应用被关闭），请重新开始`。

## Settings

`AgnesSettings` 字段与 Android 相同。

| 字段 | 存储 | 默认 |
|---|---|---|
| `apiKey` | Keychain | `""` |
| `baseUrl` | UserDefaults | `https://apihub.agnes-ai.com/`（写入时强制以 `/` 结尾） |
| `textModel` | UserDefaults | `""`（必填，无默认模型） |
| `imageModel` | UserDefaults | `agnes-image-2.0-flash` |
| `videoModel` | UserDefaults | `agnes-video-v2.0` |
| `requestTimeoutSeconds` | UserDefaults | `120`（设置页不展示，保存时写回默认） |
| `customScriptCreatePrompt` | UserDefaults | null → `PromptDefaults.SCRIPT_CREATE_PROMPT` |
| `customScriptRewritePrompt` | UserDefaults | null → rewrite 默认 |
| `customStoryboardPrompt` | UserDefaults | null → storyboard 默认 |
| `customCharacterExtractPrompt` | UserDefaults | 可存，第一版设置页不展示 |

空/空白自定义提示词经 `PromptResolver` 回退到 `PromptDefaults`。文案从 Android `PromptDefaults.kt` 原样拷贝（创作、改写、分镜；角色提取常量一并拷贝供后补）。

连通测试：先保存，再 `POST v1/chat/completions`，user = `ping`，temperature 0，max_tokens 8。只测文本模型。

## Generation Pipeline

`GenerationCoordinator` 用 Swift `Task` + actor 串行队列。同一 `(projectId, episodeId, stage)` 已在跑则忽略新请求（对应 Android WorkManager `KEEP`）；用户确认覆盖后以 `forceRegenerate` 取消旧任务再开新任务（对应 `REPLACE`）。

第一版只有 episode 1，unique key 仍带 `episodeId`，方便后补多集。

阶段：

| stage | UseCase | 远程 |
|---|---|---|
| `text` | `GenerateProjectScriptUseCase` | `POST v1/chat/completions` |
| `rewrite` | `RewriteEpisodeScriptUseCase` | 同上 |
| `storyboard` | `GenerateStoryboardsUseCase` | 同上，解析 JSON 数组 |
| `image` | `GenerateStoryboardImagesUseCase` | `POST v1/images/generations` |
| `video` | `GenerateStoryboardVideosUseCase` | `POST v1/videos` + `GET v1/videos/{id}` |
| `final_video` | `ComposeFinalVideoUseCase` | 无网络 |
| `full` | 顺序 `text → storyboard → image → video → final_video` | 中途失败即停 |

第一版 coordinator **不实现** `character_extract` / `character_image`。全流程也不自动出角色图；分镜图全部文生图。

### 剧本

- story prompt 优先 episode.`content`，空则项目 `prompt`。
- system = 创作提示词；temperature 0.7；max_tokens 4000。
- user 模板与 Android `buildUserPrompt` 相同（标题、提示词、风格、受众、画幅、镜头数、单镜时长）。
- 写入 `episode.scriptContent`，`episode.status = COMPLETED`，镜像 `project.generatedScript`。
- 聊天解析用 `extract`（允许 `reasoning_content` 回退）。空文本失败。

### 改写

- 要求 episode.`content` 非空。
- temperature 0.7；max_tokens 6000。
- 过程中 `episode.status = REWRITING`，结束 `COMPLETED` / `FAILED`。

### 分镜

- 只读当前集 `scriptContent`，禁止回退 `project.generatedScript`。
- temperature 0.3；max_tokens 10000。
- 剧本含 `## S01` 场景头则要求「一场景一镜」；否则用 `project.shotCount`。
- 解析 JSON 数组字段：`shot_number`, `scene`, `action`, `dialogue`, `camera`, `image_prompt`, `video_prompt`, `duration_seconds`, `character_names`。
- `finish_reason = length` 且内容为空视为截断失败。
- 保存：删除该集旧分镜后整表插入，`episodeId` 必填，`characterIds` 写入名字数组的 JSON。
- 分镜解析用 `extractFinalContent`（不含 `reasoning_content`）。

### 出图

- 已 `COMPLETED` 且本地文件存在则跳过。
- `size = 1024x768`，`n = 1`，`extra_body.response_format = url`。
- 第一版不传 `extra_body.image`。
- URL 取 `data[0].url` 或顶层 `url`。
- 下载到 `generated/<projectId>/shot_<shotId>_image.<ext>`。
- **失败策略（相对 Android 的有意简化）：** 每镜顺序生成；任一镜失败则该阶段 UseCase 返回 failure，已完成的镜头保留，项目 `FAILED` + 第一条错误，「全部生成」在该步停止。全部跳过或全部成功则 success。用户再点出图/出视频时，已完成且本地文件仍在的镜头继续跳过。不采用 Android「部分新生成仍 `Result.success`、项目却标 `FAILED`」的语义。

### 出视频

- 已完成且本地文件存在则跳过。
- 无图不可生成。
- 请求：`model`, `prompt`, `num_frames`, `frame_rate = 24`, `width = 768`, `height = 1152`, `image` = 本地文件 data URI（按扩展名 png/webp/jpeg）否则 `shot.imageUrl`, `mode = ti2vid`。
- prompt = `videoPrompt`、`action`、`camera` 非空项用 `。` 拼接，再加 `。请使用中文对白与中文旁白。`
- `num_frames`：`requested = max(duration,1)*24`，`capped = min(requested, 441)`，`n = max(1, (capped-1)/8)`，`num_frames = n*8+1`。
- 创建响应 `status == completed` 且有 URL（`metadata.url` / `video_url` / `url` / `remixed_from_video_id`）则不等待；否则每 10 秒 `GET v1/videos/{taskId}`，最多 60 次。`failed` 抛 `error.message`。超时文案：`Video generation timed out`。
- 下载到 `generated/<projectId>/shot_<shotId>_video.<ext>`。

### 成片

- 无网络。输入为该集全部镜头的本地视频路径，按 `shotNumber` 升序。
- 输出：`generated/<projectId>/episode_<episodeId>/final_video.mp4`。已有文件先删。
- 用 `AVMutableComposition` + `AVAssetExportSession`（`passthrough` / `AVAssetExportPresetPassthrough`）。不重编码。
- 镜头视频轨 MIME、尺寸、旋转，以及音频采样率/声道必须一致，否则失败，文案：`分镜视频参数不一致，无法在本机无转码合成 MP4`。
- 空列表：`请先生成并下载全部分镜视频后再合成成片`。缺文件：`分镜 #N 的本地视频不存在，请重新生成视频`。
- 成功写入 episode 的 `finalVideo*`，并镜像到 project 的 `finalVideo*`。

Auth：所有 Agnes 请求 `Authorization: Bearer <apiKey>`。超时 connect/read/write 均为 `requestTimeoutSeconds`。下载器单独 session，不带鉴权头，超时 120s。扩展名从 URL path 取 2–5 位字母数字，否则图默认 `jpg`、视频默认 `mp4`。

聊天解析候选顺序与 Android `ChatResponseTextExtractor` 对齐：`output_text`，`choices[].text`，`message.content`（字符串或 content-part 数组），`message.text`，`delta.content`，`output[]`。`extract` 在上述皆空时回退 `reasoning_content`；`extractFinalContent` 不回退。

## Screens

SwiftUI `NavigationStack`。首页三个入口。

| 页面 | 行为 |
|---|---|
| Home | 设置、新建、项目列表 |
| Create | 标题、创意必填。风格默认「现代短剧」，受众「大众受众」，画幅 `9:16`。镜头数、单镜时长 > 0。保存创建项目 + episode 1，push 详情 |
| Project list | `updatedAt` 倒序。点进详情。删除：停任务、删四表中该项目行、删 `generated/<id>/` |
| Detail | 按钮：全部生成、剧本、改写、分镜、出图、出视频、成片、取消。入口：剧本、分镜、图库、镜头视频、成片。生成中禁用按钮，约 1.5s 从库刷新进度（出图/出视频显示 completed/total 和当前 PROCESSING 镜头）。展示 `status` / `currentStage` / `errorMessage` |
| Script | 只读 `episode.scriptContent` |
| Storyboard | 每镜卡片，可改 `imagePrompt` / `videoPrompt` 并保存 |
| Gallery | 分镜图网格，只读 |
| Player | 镜头模式：按镜播放，可上一镜/下一镜，本地文件优先否则远程 URL。成片模式：播 episode 本地成片 |
| Settings | API Key、Base URL、三个模型、保存、测文本连通、进入提示词 |
| Prompts | 创作 / 改写 / 分镜三 tab。保存或恢复默认。脏 tab 离开要确认 |

详情预检（失败时 alert，不发任务）：

- 除成片外，API Key 为空不可跑。
- 改写需要非空 `content`。
- 分镜需要非空 `scriptContent`。
- 出图、出视频、成片需要至少一条分镜。
- 出视频需要每镜都有图（本地文件或 URL）。
- 成片需要每镜都有本地视频文件。

覆盖已有内容（已有剧本/分镜/图/视频/成片）前确认。取消：`CANCELLED`，停 coordinator 中该集任务。

进度文案语言与 Android 详情页一致即可（中文阶段名：剧本 / 分镜 / 出图 / 出视频 / 成片）。

## Error Handling

- 项目行保存 `errorMessage`；详情页展示，新任务开始时清空。
- Agnes 缺 Key / 缺模型：UseCase 立即 failure，不发请求。
- 聊天空内容：`Agnes 未返回脚本文本，请检查文本模型是否支持 chat/completions`（剧本）；分镜对应截断/空 JSON 失败。
- 视频超时：`Video generation timed out`。
- 拼接参数不一致：固定中文文案，不尝试转码。
- 取消与失败可区分：取消不覆盖为 `FAILED`。
- 不删除远端 Agnes 上的任务或文件。

## Testing

不写 UI 截图测试。用 XCTest（可在 macOS 跑的纯逻辑 target，避免必须起模拟器）：

- `ChatResponseTextExtractor`：字符串 content、parts 数组、`output_text`、`reasoning_content` 回退与否。
- 分镜 JSON 解析：合法数组、缺字段、截断。
- `durationToNumFrames`：1s → 17（`n = max(1, (24-1)/8) = 2`，`2*8+1`）；时长足够大时封顶 441。
- 详情预检：缺 Key、缺剧本、缺图、缺本地视频。
- Composer：输入空、缺文件、参数不一致（用构造的失败条件，不依赖真实 mp4 也可测校验分支）。

有 Xcode 时再跑 iOS target 编译。本机缺 Xcode 不算实现失败，但必须记录。

## Out Of Scope Follow-Ups

按鸿蒙追齐 Android 的方式后补，不在本 spec 实现：

1. 多集 chips、删集、并行 worker。
2. 角色提取 / 角色列表 / 角色图 / 强制重生成。
3. 分镜绑角色 + 参考图 base64（长边 ≤ 768，JPEG 68）。
4. 图库/播放器单张删除、成片删除、保存相册。
5. API 日志环（内存 100 条，body 32KB，data URI 脱敏）。
6. 出图/出视频部分成功仍让 full pipeline 继续（若产品要与 Android 完全一致）。

## Verification

实现后：

```text
# 有 Xcode
cd ZdramaIOS && xcodebuild -scheme Zdrama -destination 'platform=iOS Simulator,name=iPhone 16' test

# 无模拟器时至少
xcodebuild -scheme Zdrama -destination 'generic/platform=iOS' build
```

环境缺失时记录真实错误，不伪装成已验证。
