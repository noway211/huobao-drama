# Zdrama iOS Objective-C 客户端设计

## Context

仓库已有 SwiftUI 客户端 `ZdramaIOS/`，功能对齐 Android 单集制作闭环：本地 SQLite、直连 Agnes、串行生成、本地无转码拼接。该工程继续保留。

本次新增一套并列的纯 Objective-C 实现，不改 Swift 工程，不与 Swift 混编，不接 Node 后端，不共享 Android/KMP 代码。行为以当前 Swift 实现和 `docs/superpowers/specs/2026-09-29-ios-zdrama-native-design.md` 为准。Swift 文档里「显示名：火宝短剧」「textModel 默认空」两处已过时：显示名是「视频短剧」，文本模型默认 `agnes-2.0-flash`。

## Goal

在仓库根目录新增 `ZdramaIOSObjC/`，用 Objective-C + UIKit 实现与 Swift 版相同的单集闭环：

1. 配置 Agnes API Key、Base URL、文本/图片/视频模型，并测试文本连通。
2. 创建项目（标题、创意、风格、受众、画幅、镜头数、单镜时长）。
3. 生成剧本、改写、拆分镜、逐镜出图、逐镜出视频、无转码拼接成片。
4. 项目、分镜、媒体路径保存在本机。杀进程后未完成任务标失败，可重试。

成功标准：配置可用 Agnes 凭证后，在真机或模拟器上，一个单集项目可以从空白走到可播放的 `final_video.mp4`。逻辑测试（JSON 解析、帧数公式、预检、设置缺省、SQLite 读写）用 XCTest，不依赖模拟器。

## Non-Goals

- 不删除、不修改 `ZdramaIOS/`。
- 不引入 Swift、GRDB、FMDB、CocoaPods、Swift Package。
- 不调用 `huobao-drama` 的 `/api/v1`，不读 Web 或其他端的数据库。
- 不做多集 UI、角色提取、角色图、分镜绑角色、参考图。
- 不保存系统相册，不提供单张图片/视频/成片删除（删除整个项目除外）。
- 不做 API 日志页、TTS、字幕、BGM、多厂商适配。
- 不上 `BGProcessingTask`。杀进程即中断。
- 不把工程并入根 `package.json`。

## Approach

纯 Objective-C 静态库 + UIKit App。

- 核心库 `ZdramaCoreObjC`：模型、SQLite、Agnes、设置、提示词、媒体、生成调度。无 UIKit 页面。
- App `ZdramaObjC`：UIKit，只负责导航、表单和展示。
- SQLite 用系统 `libsqlite3`。HTTP 用 `NSURLSession`。密钥用 Keychain。成片用 `AVFoundation`。
- 工程用 `project.yml` + xcodegen 生成 `ZdramaObjC.xcodeproj`。

不采用「业务和界面混在一个 target」：页面会直接写 SQL。不采用「界面 Objective-C、核心继续链 Swift」：工程里仍有 Swift，不符合本次范围。

## App Identity

| 项 | 值 |
|---|---|
| 目录 | `ZdramaIOSObjC/` |
| 显示名 | 视频短剧 |
| Bundle ID | `com.huobao.zdrama.objc` |
| 最低系统 | iOS 17 |
| 方向 | 仅竖屏 |
| 数据库文件 | `Application Support/zdrama.db`，schema version 12 |

Bundle ID 与 Swift 版 `com.huobao.zdrama` 不同，两套 App 可同时装在一台模拟器上。数据库文件各自在自己的沙盒里，不互相读写。

## Layout

```text
ZdramaIOSObjC/
  project.yml
  README.md
  ZdramaCoreObjC/
    Domain/Models/
    Domain/UseCases/
    Data/Local/
    Data/Remote/
    Data/Settings/
    Data/Prompt/
    Data/Media/
    Generation/
  ZdramaObjC/
    App/
    Features/Home/
    Features/Create/
    Features/ProjectList/
    Features/ProjectDetail/
    Features/Script/
    Features/Storyboard/
    Features/Gallery/
    Features/Player/
    Features/Settings/
    Info.plist
  ZdramaCoreObjCTests/
```

依赖方向：

- Features 只调 UseCase 和只读查询。不拼 SQL，不直接发 Agnes 请求。
- UseCase 调仓库。成功和失败都写数据库。
- Remote 只做协议和解析，不写库。
- 媒体路径只由媒体层给出。
- 页面从数据库刷新，不把进行中的任务对象当数据源。

## Domain And Schema

枚举持久化为 `name` 字符串。未知值回退：`ProjectStatus` → `DRAFT`，`GenerationStage` → `NONE`，`AssetStatus` → `PENDING`，`EpisodeStatus` → `DRAFT`。

```text
ProjectStatus:   DRAFT | PROCESSING | COMPLETED | FAILED | CANCELLED
GenerationStage: NONE | TEXT | STORYBOARD | IMAGE | VIDEO | FINAL_VIDEO
AssetStatus:     PENDING | PROCESSING | COMPLETED | FAILED
EpisodeStatus:   DRAFT | REWRITING | COMPLETED | FAILED
```

模型字段、四张表和列名与 Swift/Android 当前实现一致，不另起一套：

- `projects`
- `episodes`（创建时插入 `episode_number = 1`）
- `storyboards`
- `characters`（建表，第一版无读写）

时间戳用 epoch 毫秒 `INTEGER`。第一版直接建 version 12，无历史迁移。

冷启动：把仍为 `PROCESSING` 的项目标 `FAILED`，`error_message = 生成任务中断（应用被关闭），请重新开始`。同一规则用于仍在 `PROCESSING` 的分镜图片/视频和成片状态。取消中的任务不改写成失败。

## Settings

| 字段 | 存储 | 默认 |
|---|---|---|
| `apiKey` | Keychain，service `com.huobao.zdrama.objc`，account `api_key` | `""` |
| `baseUrl` | NSUserDefaults | `https://apihub.agnes-ai.com/`，保存时保证以 `/` 结尾 |
| `textModel` | NSUserDefaults | `agnes-2.0-flash` |
| `imageModel` | NSUserDefaults | `agnes-image-2.0-flash` |
| `videoModel` | NSUserDefaults | `agnes-video-v2.0` |
| `requestTimeoutSeconds` | NSUserDefaults | `120`，设置页不展示 |
| 自定义提示词 | NSUserDefaults | 空白则回退 `PromptDefaults` |

`PromptDefaults` 从 Swift 版原样拷贝创作、改写、分镜、角色提取四段文案。设置页只编辑前三段。

连通测试：先保存当前表单，再 `POST v1/chat/completions`，user 消息 `ping`，temperature 0，max_tokens 8。HTTP 2xx 即成功，不要求响应 `content` 非空。只测文本模型。

## Generation

`ZDGenerationCoordinator` 用一条串行 `NSOperationQueue`（`maxConcurrentOperationCount = 1`）跑任务。同一 `(projectId, episodeId, stage)` 已在队列中则忽略；`forceRegenerate` 先取消该任务再入队。第一版只有 episode 1，key 仍带 `episodeId`。

| stage | 行为 |
|---|---|
| `text` | 创作剧本，temperature 0.7，max_tokens 4000 |
| `rewrite` | 改写，temperature 0.7，max_tokens 6000 |
| `storyboard` | 拆分镜，temperature 0.3，max_tokens 10000，解析 JSON 数组 |
| `image` | `POST v1/images/generations`，`1024x768`，`n = 1` |
| `video` | `POST v1/videos`，未完成则每 10 秒 `GET v1/videos/{id}`，最多 60 次 |
| `final_video` | 无网络，`AVMutableComposition` + `AVAssetExportPresetPassthrough` |
| `full` | 顺序 `text → storyboard → image → video → final_video`，中途失败即停 |

协议细节与 Swift 版相同，不在 Objective-C 里改参数：

- 鉴权头 `Authorization: Bearer <apiKey>`。
- 剧本 user 模板、分镜 JSON 字段、出图 URL 取值、出视频 `num_frames` 公式、下载路径规则，都按 Swift 当前实现。
- `num_frames`：`requested = max(duration,1)*24`，封顶 441，再对齐到 `n*8+1`。1 秒得到 17。
- 聊天正文提取顺序与 Swift `ChatResponseTextExtractor` 相同。剧本允许回退 `reasoning_content`；分镜不允许。
- 出图/出视频：已完成且本地文件还在则跳过。任一镜失败则该阶段失败，已完成镜头保留。
- 成片输出 `generated/<projectId>/episode_<episodeId>/final_video.mp4`。参数不一致、缺文件、空列表都失败，不转码。
- 取消写 `CANCELLED`，不覆盖成 `FAILED`。

## Screens

UIKit + `UINavigationController`。首页三个入口：设置、新建、项目。

| 页面 | 行为 |
|---|---|
| Home | 设置、新建、项目列表 |
| Create | 标题、创意必填。风格默认「现代短剧」，受众「大众受众」，画幅 `9:16`。镜头数和单镜时长 > 0。保存后进入详情 |
| Project list | `updatedAt` 倒序。删除时停任务、删该项目相关行、删 `generated/<id>/` |
| Detail | 全部生成、剧本、改写、分镜、出图、出视频、成片、取消。入口：剧本、分镜、图库、镜头视频、成片。生成中禁用按钮，约 1.5 秒从库刷新 |
| Script | 只读当前集剧本 |
| Storyboard | 每镜可改 `imagePrompt` / `videoPrompt` 并保存 |
| Gallery | 分镜图只读网格 |
| Player | 镜头模式按镜播放，本地文件优先；成片模式播本地成片 |
| Settings | API Key、Base URL、三个模型、保存、测连通、进入提示词 |
| Prompts | 创作 / 改写 / 分镜。保存或恢复默认。未保存离开要确认 |

详情预检失败只弹窗，不入队：

- 除成片外，API Key 为空不可跑。
- 改写需要非空创意。分镜需要非空剧本。
- 出图、出视频、成片至少要有一条分镜。
- 出视频每镜都要有图。成片每镜都要有本地视频。
- 覆盖已有剧本、分镜、图、视频、成片前先确认。

## Error Handling

- 项目行保存 `errorMessage`。新任务开始时清空。详情页展示。
- 缺 Key 或必填模型：UseCase 直接失败，不发请求。
- HTTP 非 2xx：记录状态码和响应体。
- 聊天空内容、分镜截断、视频超时、拼接参数不一致，文案与 Swift 版相同。
- 不删除 Agnes 远端任务或文件。

## Testing

`ZdramaCoreObjCTests` 链静态库，用 XCTest。不写 UI 截图测试。

- 聊天正文提取：字符串 content、content parts、`output_text`、`reasoning_content` 回退与否。
- 分镜 JSON：合法数组、缺字段、截断。
- `num_frames`：1 秒 → 17；超长封顶 441。
- 预检：缺 Key、缺剧本、缺图、缺本地视频。
- 设置：空白 Base URL / 图片模型 / 视频模型回退默认；文本模型默认 `agnes-2.0-flash`。
- SQLite：建库、插入项目和 episode 1、按 `updatedAt` 倒序、删除项目。
- 拼接校验：空列表、缺文件。不依赖真实转码成功。

有 Xcode 时编译 App target。缺 Xcode 或模拟器时记录真实错误，不把编译未跑写成已通过。

## Verification

```text
cd ZdramaIOSObjC
xcodegen generate
xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build
xcodebuild -scheme ZdramaCoreObjC -destination 'platform=iOS Simulator,name=iPhone 16' test
```

模拟器名称以本机 `xcrun simctl list devices available` 为准。测试 scheme 跑逻辑用例；没有可用模拟器时至少完成 generic iOS 编译。
