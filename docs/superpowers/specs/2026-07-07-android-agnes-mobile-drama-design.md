# Android 端 Agnes 短剧生成实现计划

## Context

用户希望参考当前 `huobao-drama` 工程，在 Android 手机端独立实现短剧生成能力。约束是：

- 所有核心流程在手机端完成，不依赖当前 Node 后端运行。
- Agnes API Key 由用户在 App 内手动设置。
- 不需要音色、TTS、试听、配音生成。
- 手机端不用 Compose 模式：Android UI 不使用 Jetpack Compose，采用传统 XML + ViewBinding/RecyclerView/Material Components。
- 手机端 MVP 不做后端式 FFmpeg compose 合成模式：不做字幕烧录、不做音频混流、不做复杂本地合成。每个分镜生成独立视频，App 内按顺序展示和连续播放。
- 需要支持受限 skill：仅支持本地 Prompt 模板、固定参数、固定 JSON 输出和 Agnes 文本接口调用；不支持任意代码执行、文件读写、系统命令、插件市场或后端工具调用。

当前工程仍有重要参考价值：可以复用其 Agnes 请求结构、图片/视频生成状态机、短剧实体建模、分镜生成流程、skill/agent 的 Prompt 分工思路和错误处理思路。但 TypeScript 后端代码本身不能直接搬到 Android，需要用 Kotlin 重写。

## Recommended Direction

推荐做一个独立 Android App：

- Kotlin + Android XML 布局 + ViewBinding。
- Retrofit/OkHttp 调 Agnes OpenAI-compatible API。
- Room 保存项目、角色、场景、分镜、图片任务、视频任务、受限 skill 配置。
- EncryptedSharedPreferences/Android Keystore 保存用户手动输入的 Agnes API Key。
- WorkManager + ForegroundInfo 执行长耗时生成任务。
- ViewModel + StateFlow 暴露 UI 状态。
- Media3/ExoPlayer 播放分镜视频。
- 不内置服务器，不运行 Node，不接现有后端。

不推荐首版做：

- Android 本地 FFmpeg 合成/拼接。
- 字幕烧录。
- TTS/音色。
- 复杂 agent tool runtime。
- 多 provider 插件化。
- 后台无人值守长时间生成完整大片。

## MVP Goal

MVP 完成这个闭环：

1. 用户设置 Agnes API Key 和模型配置。
2. 用户输入短剧主题、风格、目标受众、镜头数、画幅、单镜头时长。
3. App 调 Agnes 文本模型生成结构化短剧数据。
4. App 生成角色、场景、分镜。
5. App 为每个分镜调用 Agnes 图片接口生成图片。
6. App 为每个分镜调用 Agnes 视频接口生成视频。
7. App 本地保存生成记录和媒体 URL/文件。
8. App 用列表和播放器按顺序播放分镜视频。

MVP 的“短剧成片”表现形式是：分镜视频列表 + 连续播放队列。不是单一合成 MP4 文件。

## Android Runtime Architecture

Room 是本地 source of truth。所有长任务只更新 Room，UI 不直接依赖 worker 内存状态。

数据流：

```text
Agnes API -> Worker/Repository -> Room -> Repository Flow -> ViewModel StateFlow -> XML/ViewBinding UI
```

具体约束：

- DAO 暴露 `Flow<List<ProjectEntity>>`、`Flow<ProjectDetail>`、`Flow<List<StoryboardEntity>>`。
- Repository 负责把 Room entity 映射为 domain model。
- ViewModel 使用 `StateFlow` 暴露 screen state。
- Fragment/Activity 使用 ViewBinding 收集 ViewModel state，不直接轮询网络。
- WorkManager/ForegroundService 只通过 Repository 写入 Room 状态。
- 屏幕旋转、Fragment 重建、App 回前台时，UI 从 Room 自动恢复。
- App 启动时扫描 `processing` 状态任务，提示用户继续轮询、重试或标记失败。
- MVP 同一时间只允许一个 project 主生成任务；后续再支持队列。

## Foreground Work And Resume Strategy

短剧生成耗时较长，尤其是视频任务。不能依赖 Activity 生命周期。

推荐：

- 使用 WorkManager 执行主 pipeline。
- Worker 设置 `ForegroundInfo`，生成中显示常驻通知。
- Work constraints 要求网络可用。
- 文本、图片、视频阶段都写入 Room 状态和错误信息。
- 用户取消任务时，同时取消 WorkRequest 并把 ProjectEntity 状态改为 `cancelled`。
- 进程被杀后，下一次启动读取 Room 中的 `processing` task：
  - 有 Agnes task id 的图片/视频任务继续轮询。
  - 没有 task id 的本地阶段允许重新执行。
  - 超过最大等待时间的任务标记为 `failed`，展示“继续检查”或“重试”。

轮询建议：

- 文本生成：普通 complete 请求，不轮询。
- 图片 task：每 5 秒轮询一次，最多 120 次或 10 分钟。
- 视频 task：每 10 秒轮询一次，最多 180 次或 30 分钟；具体可根据 Agnes 实际耗时调整。

## Model Configuration

设置页必须支持：

- Agnes API Key。
- Base URL，默认 `https://apihub.agnes-ai.com`。
- Text model。
- Image model，默认 `agnes-image-2.0-flash`。
- Video model，默认 `agnes-video-v2.0`。
- 请求超时配置，MVP 可固定。

文档和代码不应保留未定义占位模型名。Text model 如果 Agnes 后台没有固定默认值，必须由用户设置；设置页提供“测试文本模型”按钮。

连接测试：

- API Key 测试：发起轻量 chat completions 请求。
- 图片模型测试：可选，生成一张极小测试图，避免默认消耗。
- 视频模型测试：不建议默认执行，成本高，只做配置格式校验。

## Agnes API Implementation Details

### Common

- Base URL: `https://apihub.agnes-ai.com`
- Auth: `Authorization: Bearer {userApiKey}`
- 统一通过 OkHttp interceptor 注入 Authorization。
- 所有 Agnes 请求只允许 HTTPS。
- 所有错误响应保存：HTTP status、provider error code、message、task id。
- 日志不记录 API Key。

### Text Generation

使用 OpenAI-compatible chat completions：

- `POST /v1/chat/completions`
- 用于生成结构化 JSON：剧本、角色、场景、分镜。
- Android 不实现 Mastra agent runtime。
- 采用“强约束 prompt + JSON schema 文本说明 + 本地 JSON 解析/修复”的方式。

建议分步生成：

1. `idea_expander`
2. `drama_structure_generator`
3. `character_designer`
4. `scene_designer`
5. `storyboard_breaker`
6. `continuity_checker`
7. `image_prompt_refiner`
8. `video_prompt_refiner`

### Image Generation

参考当前后端：`backend/src/services/adapters/agnesai-image.ts`

- `POST /v1/images/generations`
- 文生图 body：
  - `model`
  - `prompt`
  - `size`
  - `n: 1`
  - `extra_body.response_format = "url"`
- 图生图 body：
  - 在 `extra_body` 中追加 `image: [urlOrDataUri]`
  - 保留 `response_format: "url"`

响应兼容：

- 同步 URL：`data[0].url` 或 `url`。
- 同步 base64：`data[0].b64_json`，即使请求 URL 也要兼容，保存为本地图片文件。
- 异步 task：`task_id` 或明确的 task 字段。
- 如果响应同时包含普通 `id` 和 `data[0].url`，Android 端应优先使用 URL，避免把普通响应 id 误判为 task id。
- 异步轮询：`GET /v1/images/task/{taskId}`。
- 轮询间隔：5 秒。
- 最大等待：120 次或 10 分钟。

MVP 优先文生图生成每个分镜首帧图。后续再支持角色图、场景图、图生图重绘。

### Video Generation

参考当前后端：`backend/src/services/adapters/agnesai-video.ts`

- `POST /v1/videos`
- 单图生视频：用分镜图片作为参考图。
- 默认模型：`agnes-video-v2.0`。
- `frame_rate`: 24。
- `num_frames` 必须满足 `8n + 1` 且 `<= 441`。
- 对 5 秒、24 fps，推荐 frames 为 121。
- 按画幅换算 `width/height`。
- 异步轮询：`GET /v1/videos/{taskId}`。
- 轮询间隔：10 秒。
- 最大等待：180 次或 30 分钟。

响应 URL 兼容：

- `video_url`
- `url`
- `remixed_from_video_id` 对应的视频 URL 字段
- provider 返回的 data 嵌套结构

视频任务超时后进入 `failed`，保留 `taskId`，用户可选择“继续检查”或重新生成。

## Limited Skill System

Android 端需要保留“skill”概念，但必须是受限能力，不复制当前后端/Claude Code 式 skill 运行时。

### Skill Scope

允许：

- 本地内置 skill 定义。
- 用户在 App 内启用/禁用可选 skill。
- Prompt 模板变量替换。
- 调 Agnes chat completions。
- 要求模型输出固定 JSON 或纯文本 prompt。
- 本地解析和校验输出。
- 单次 JSON 修复重试。

禁止：

- 执行 Kotlin/JS/脚本代码。
- 访问任意文件系统路径。
- 调用系统命令。
- 任意 HTTP 工具调用。
- 动态安装远程 skill。
- 读取通讯录、相册、定位等 Android 权限数据。
- 访问 API Key 明文。
- 绕过 App 定义的数据模型直接修改数据库。

### Skill Runtime Contracts

每个 skill 必须声明：

- `id`
- `name`
- `version`
- `required`
- `enabledByDefault`
- `modelType`: `text`
- `temperature`
- `maxOutputTokens`
- `inputSchema`
- `outputSchema`
- `outputMode`: `json_object`、`json_array` 或 `text_prompt`
- `promptTemplate`

规则：

- 必需 skill 不允许被用户禁用，只允许覆盖 temperature 或追加说明。
- 可选 skill 可禁用，但必须定义 fallback。
- `json_repair` 只作用于 `json_object` 和 `json_array` 输出，不作用于 `text_prompt`。
- `text_prompt` 输出需要定义最大长度、是否允许换行、禁用词处理。
- skill version 升级时，Room 中旧 `SkillConfigEntity` 要迁移或重置为默认。

### Built-in Skills

#### Core Generation Skills

- `idea_expander`
  - 用途：把用户一句话主题扩写成适合短剧生成的故事设定。
  - 输入：主题、目标受众、风格、时长、限制词。
  - 输出：`title`、`logline`、`synopsis`、`tone`、`visualStyle`。
- `drama_structure_generator`
  - 用途：生成短剧基础结构。
  - 输入：扩写后的故事设定、镜头数、画幅、单镜头时长。
  - 输出：标题、简介、角色数组、场景数组。
- `character_designer`
  - 用途：补全角色外貌和视觉一致性描述。
  - 输入：角色列表、故事风格、目标受众。
  - 输出：角色数组，包含 `name`、`role`、`personality`、`appearance`、`visualPrompt`。
- `scene_designer`
  - 用途：补全场景视觉设定。
  - 输入：场景列表、故事风格、画幅。
  - 输出：场景数组，包含 `name`、`description`、`atmosphere`、`visualPrompt`。
- `storyboard_breaker`
  - 用途：拆解分镜。
  - 输入：标题、简介、角色、场景、镜头数。
  - 输出：分镜数组。

#### Prompt Refinement Skills

- `image_prompt_refiner`
  - 用途：生成 Agnes 图片 prompt。
  - 输入：分镜描述、角色视觉描述、场景视觉描述、风格、画幅。
  - 输出：单条图片 prompt。
- `video_prompt_refiner`
  - 用途：生成 Agnes 视频 prompt。
  - 输入：分镜描述、图片 prompt、动作、镜头运动、风格、时长。
  - 输出：单条视频 prompt。
- `continuity_checker`
  - 用途：检查角色、场景、分镜之间的一致性。
  - 输入：角色、场景、分镜数组。
  - 输出：`issues[]` 和 `fixedStoryboards[]`。

#### Utility Skills

- `json_repair`
  - 用途：修复模型输出的非标准 JSON。
  - 输入：原始模型输出、目标 schema 描述、解析错误。
  - 输出：修复后的 JSON。
- `content_safety_rewriter`
  - 用途：把不适合生成或可能被 Agnes 拒绝的内容改写成安全表达。
  - 输入：原 prompt、失败原因或安全规则。
  - 输出：改写后的 prompt。
- `generation_failure_analyzer`
  - 用途：分析 Agnes 图片/视频失败原因，给出可执行重试建议。
  - 输入：接口错误码、错误信息、当前 prompt、任务类型。
  - 输出：`reason`、`retryable`、`suggestedPrompt`、`suggestedAction`。

#### Optional Post-MVP Skills

- `title_generator`
- `style_preset_generator`
- `localized_copywriter`

首版必须支持 Core Generation Skills、Prompt Refinement Skills 和 Utility Skills。Optional Post-MVP Skills 可以先只保留定义，不接入主流程。

### Skill Runtime

新增本地 `SkillEngine`：

1. 根据 skill id 读取内置定义。
2. 校验输入字段完整性。
3. 用变量替换生成 prompt。
4. 调 Agnes chat completions。
5. 根据 `outputMode` 提取 JSON 或文本。
6. 校验必填字段、长度、数组数量和枚举值。
7. JSON 输出失败时调用 `json_repair` 一次。
8. 返回 typed result 给 usecase。

`SkillEngine` 不直接操作 UI，不直接操作网络以外的系统资源；写库由 repository/usecase 完成。

### Skill Storage

Room 增加：

- `SkillConfigEntity`
  - `id`
  - `version`
  - `enabled`
  - `temperatureOverride`
  - `promptAppendix`
  - `updatedAt`

首版只保存启用状态和少量参数，不支持用户编辑完整 prompt。后续可以增加“高级模式”让用户编辑 prompt，但仍不允许工具调用或代码执行。

### Safety And Debugging

- 默认不保存完整 prompt 和模型原始输出。
- 调试模式可以本地保存最近 N 次 skill 调用，但必须可清空。
- skill 调用日志只记录 skill id、耗时、状态、错误摘要。
- 不记录 API Key。
- crash report 默认不上传用户剧本和 prompt。
- 用户导出项目时，默认不包含 API Key 和调试日志。
- 所有 skill 输出必须经过 JSON 解析和字段校验，不能把模型文本直接当业务数据写入。

## Android App Architecture

### Packages

可以先做单 App module，按 package 分层：

- `data.local`
  - Room database、DAO、entities。
- `data.remote`
  - Retrofit services、OkHttp interceptors、Agnes request/response DTO。
- `data.repository`
  - DramaRepository、GenerationRepository、SkillRepository。
- `domain.model`
  - App 内部业务模型。
- `domain.usecase`
  - CreateDramaUseCase、GenerateImagesUseCase、GenerateVideosUseCase、RetryStoryboardUseCase。
- `skill`
  - BuiltInSkillRegistry、SkillEngine、SkillInputValidator、SkillJsonParser。
- `worker`
  - WorkManager workers。
- `ui.settings`
  - API Key 和模型设置页。
- `ui.create`
  - 短剧创建页。
- `ui.project`
  - 项目详情/进度页。
- `ui.storyboard`
  - 分镜详情页。
- `ui.player`
  - 连续播放页。
- `ui.skills`
  - 受限 skill 设置页。

### UI Technology

不用 Jetpack Compose。

使用：

- XML layout。
- ViewBinding。
- RecyclerView + ListAdapter。
- Material Components。
- Fragment 或 Activity + Navigation Component。
- ViewModel + StateFlow。
- Media3 PlayerView 播放视频。

## UI Navigation And State Screens

### Settings Screen

- API Key 输入、验证、删除。
- Base URL 配置。
- Text/Image/Video model 配置。
- 连接测试。
- 清理调试日志。

### Create Screen

- 主题。
- 风格。
- 目标受众。
- 镜头数。
- 画幅。
- 单镜头时长。
- 开始生成按钮。

### Project Detail Screen

- 总进度。
- 当前阶段。
- skill 阶段状态。
- 图片生成状态。
- 视频生成状态。
- 错误卡片和重试入口。
- 分镜列表。

### Storyboard Detail Screen

- 分镜描述。
- 角色和场景。
- 图片 prompt。
- 视频 prompt。
- 图片预览。
- 视频预览。
- 重试图片/重试视频。

### Player Screen

- Media3 连续播放分镜视频。
- 上一段/下一段。
- 重新生成当前分镜视频。
- 优先播放 `localVideoPath`；仅当本地文件缺失时临时 fallback 到 `videoUrl` 并提示重新下载。

### Skill Settings Screen

- 内置 skill 列表。
- 必需 skill 只读显示，不能关闭。
- 可选 skill 可启用/禁用。
- temperature 覆盖。
- 恢复默认。

## Data Model

Room entities：

### `ProjectEntity`

- `id`
- `title`
- `prompt`
- `style`
- `targetAudience`
- `aspectRatio`
- `shotCount`
- `shotDurationSeconds`
- `status`
- `currentStage`
- `errorMessage`
- `createdAt`
- `updatedAt`

### `CharacterEntity`

- `id`
- `projectId`
- `name`
- `role`
- `personality`
- `description`
- `appearance`
- `visualPrompt`

### `SceneEntity`

- `id`
- `projectId`
- `name`
- `description`
- `atmosphere`
- `visualPrompt`

### `StoryboardEntity`

- `id`
- `projectId`
- `index`
- `title`
- `description`
- `sceneName`
- `charactersJson`
- `imagePrompt`
- `videoPrompt`
- `durationSeconds`
- `imageStatus`
- `imageTaskId`
- `imageUrl`
- `localImagePath`
- `videoStatus`
- `videoTaskId`
- `videoUrl`
- `localVideoPath`
- `errorMessage`

### `SkillConfigEntity`

- `id`
- `version`
- `enabled`
- `temperatureOverride`
- `promptAppendix`
- `updatedAt`

### Status Values

- `pending`
- `processing`
- `completed`
- `failed`
- `download_failed`
- `cancelled`

## Generation Flow

### 1. API Key Setup

- 用户进入设置页。
- 输入 Agnes API Key 和模型配置。
- App 调轻量 chat completions 请求验证 key 和 text model。
- 验证通过后写入 EncryptedSharedPreferences。

### 2. Create Project

- 用户输入主题、风格、目标受众、镜头数、画幅、时长。
- 写入 `ProjectEntity(status=processing, currentStage=text)`。
- 启动 WorkManager。

### 3. Text Structure Generation

Worker 执行：

1. 调 `SkillEngine.run("idea_expander", input)` 扩写故事设定。
2. 调 `SkillEngine.run("drama_structure_generator", input)` 生成角色和场景 JSON。
3. 调 `SkillEngine.run("character_designer", input)` 补全角色视觉描述。
4. 调 `SkillEngine.run("scene_designer", input)` 补全场景视觉描述。
5. 写入 Room。
6. 调 `SkillEngine.run("storyboard_breaker", input)` 生成分镜 JSON。
7. 调 `SkillEngine.run("continuity_checker", input)` 检查并修复角色/场景/分镜一致性。
8. 调 `image_prompt_refiner` 和 `video_prompt_refiner` 生成每个分镜的图片/视频 prompt。
9. 写入 StoryboardEntity。

错误处理：

- JSON 输出解析失败时，最多用一次 `json_repair`。
- 仍失败则项目进入 failed，展示 skill id 和错误摘要。

### 4. Image Generation

按分镜顺序或有限并发执行：

- 建议并发数：1 或 2。
- 调 Agnes image generation。
- 如果同步返回 URL，保存 `imageUrl`，随后必须下载到项目本地目录并保存 `localImagePath`。
- 如果同步返回 base64，直接写入项目本地图片文件，保存 `localImagePath`。
- 如果返回 task id，则轮询 task，完成后同样下载/写入本地。
- 只有本地文件写入成功后，`imageStatus` 才标记为 `completed`。
- UI 图片预览优先使用 `localImagePath`，远程 `imageUrl` 只作为重新下载或临时 fallback。

### 5. Video Generation

图片完成后执行：

- 用 `imageUrl` 作为参考图。
- 如果只有本地图片，需要转 data URI，注意压缩和大小限制。
- 调 Agnes video generation。
- 保存 `videoTaskId`。
- 轮询完成后保存 `videoUrl`，随后必须下载到项目本地目录并保存 `localVideoPath`。
- 只有本地视频文件写入成功后，`videoStatus` 才标记为 `completed`。
- 视频播放优先使用 `localVideoPath`，远程 `videoUrl` 只作为重新下载或临时 fallback。

### 6. Playback

- 不做 compose/merge。
- 项目详情页展示每个分镜的视频卡片。
- 播放页用 Media3 按顺序播放 `localVideoPath`。
- 本地文件缺失时临时使用 `videoUrl` fallback，并提示用户重新下载该分镜视频。
- 支持上一段/下一段。

## Media Storage And Cache Policy

图片和视频生成完成后必须下载到手机本地，资源按项目分类保存。远程 URL 只作为来源记录、重新下载和临时 fallback，不作为主展示资源。

目录策略：

- 媒体根目录：`context.getExternalFilesDir(null)/projects/{projectId}/`
- 图片目录：`context.getExternalFilesDir(null)/projects/{projectId}/images/`
- 视频目录：`context.getExternalFilesDir(null)/projects/{projectId}/videos/`
- 调试目录：`context.getExternalFilesDir(null)/projects/{projectId}/debug/`，仅调试模式启用。

文件命名：

- 分镜图片：`shot_{index}_image.{ext}`。
- 分镜视频：`shot_{index}_video.mp4`。
- 重新生成时写入新临时文件，下载完成后再原子替换旧文件，避免 UI 读取半文件。

展示策略：

- 图片预览优先使用 `localImagePath`。
- 视频播放优先使用 `localVideoPath`。
- 本地文件不存在或校验失败时，才 fallback 到远程 `imageUrl` / `videoUrl`，并触发重新下载提示。
- `completed` 状态要求本地媒体存在；如果 Agnes 已生成但本地下载失败，状态应为 `download_failed` 或 `failed`，允许用户重试下载。

清理策略：

- 项目删除时删除 `projects/{projectId}/` 整个目录。
- 提供项目级缓存大小展示。
- 提供清理单项目媒体和清理全部缓存入口。
- 低存储空间时暂停下载并提示用户。
- 导出到相册或公共目录作为后续功能，不属于 MVP。

权限：

- `getExternalFilesDir(...)` 属于 App 外部私有目录，不需要 `READ_MEDIA_*` 或存储读写权限。
- App 卸载时该目录会被系统清理；用户在系统文件管理器中可能看到这些文件。
- 导出到公共媒体库时再使用系统 Photo Picker、SAF 或对应媒体权限。

## Permissions And Network Security

AndroidManifest 需要：

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `FOREGROUND_SERVICE`
- Android 13+ 使用前台通知时需要 `POST_NOTIFICATIONS`

如后续支持公共目录导出，再按 Android 版本补媒体权限或 SAF。

网络安全：

- Agnes base URL 必须是 HTTPS。
- 默认 network security config 不允许明文 HTTP。
- 用户自定义 base URL 如果不是 HTTPS，设置页应阻止保存或显示强警告。

## Retry Strategy

粒度：

- 重试文本结构生成。
- 重试单个分镜图片。
- 重试单个分镜视频。
- 继续检查已有 Agnes task id。

不做：

- 自动无限重试。
- 全局 silent retry。

建议：

- 网络错误重试 1 次。
- API 错误先调用 `generation_failure_analyzer` 分析是否可重试。
- 如果失败原因与内容安全、prompt 过长或表达不清有关，调用 `content_safety_rewriter` 生成新的 prompt 候选。
- 用户手动确认后重试，不自动无限重试。

## Prompt And Content Constraints

- 创建项目时要求用户选择目标受众。
- 儿童/青少年题材默认禁用暴力、血腥、成人、危险行为细节。
- 图片/视频 prompt 发送前进行长度裁剪。
- Agnes 返回内容安全/审核类错误时，调用 `content_safety_rewriter`。
- 改写后的 prompt 需要用户确认后再重试。

## Security Notes

手机端手动设置 API Key 是可行的，但不是强安全方案。

必须明确：

- API Key 保存在 EncryptedSharedPreferences。
- 不写入日志。
- 不放入 crash report。
- 设置页支持删除 key。
- App 内所有请求统一通过 OkHttp interceptor 注入 Authorization。
- 如果 App 对外发布，用户自己的 key 仍可能被系统备份、Root、调试工具或恶意环境获取。

## Implementation Order

1. 新建 Android 工程骨架：Kotlin + XML + ViewBinding + Material + Room + Retrofit + WorkManager + Media3。
2. 实现设置页：输入、验证、保存、删除 Agnes API Key 和模型配置。
3. 实现 Agnes API client：chat、image generation、image task poll、video generation、video poll。
4. 实现受限 skill 基础设施：BuiltInSkillRegistry、SkillEngine、输入校验、JSON 解析/修复。
5. 实现 Room entities/DAO/repository，包括 SkillConfigEntity。
6. 实现创建项目页和项目详情页。
7. 实现文本结构生成 worker/usecase，统一通过 SkillEngine 调内置 skill。
8. 实现图片生成 worker/usecase。
9. 实现视频生成 worker/usecase。
10. 实现媒体下载和缓存策略。
11. 实现进度 UI、失败展示、单分镜重试。
12. 实现 Media3 连续播放页。
13. 真机验证完整流程。

## Verification Plan

### Unit / Local Tests

- JSON 解析：角色/场景/分镜结构化输出。
- SkillEngine：输入校验、模板变量替换、输出字段校验、JSON 修复重试。
- 内置 skill 覆盖检查：`idea_expander`、`drama_structure_generator`、`character_designer`、`scene_designer`、`storyboard_breaker`、`image_prompt_refiner`、`video_prompt_refiner`、`continuity_checker`、`json_repair`、`content_safety_rewriter`、`generation_failure_analyzer` 都有定义、schema 和测试样例。
- SkillConfigEntity：启用/禁用内置 skill 后流程行为正确；必需 skill 被禁用时主流程给出明确错误或阻止保存。
- `num_frames` 计算满足 `8n + 1` 和 `<=441`。
- Agnes request DTO 序列化正确。
- Room status 转换正确。
- 日志不包含 Agnes API Key 明文。

### Integration Tests

- 错误 API Key 返回清晰错误。
- Text model JSON 不合法时触发 `json_repair`。
- 图片同步 URL 响应。
- 图片 base64 响应。
- 图片异步 task 响应。
- 视频 task 超时。
- App 被系统杀进程后恢复项目状态。
- 必需 skill 被禁用时阻止保存或自动恢复默认。
- 图片/视频生成完成后，本地 `projects/{projectId}/images` 和 `projects/{projectId}/videos` 下存在对应文件。
- 图片/视频本地下载失败时进入 `download_failed`，允许单独重试下载。
- 视频 URL 失效后使用本地缓存播放。
- 本地文件被删除后，UI fallback 到远程 URL 并提示重新下载。
- 无网络创建/重试行为。

### Manual Device Tests

1. 首次打开 App，无 API Key 时跳设置页。
2. 输入错误 key，显示验证失败。
3. 输入正确 key，保存成功。
4. 创建一个 3 镜头短剧。
5. 成功生成角色、场景、分镜。
6. 成功生成 3 张图片。
7. 成功生成 3 个视频。
8. 播放页按顺序播放 3 个视频。
9. 断网时任务失败或暂停，并能重试。
10. 关闭 App 后重新打开，能恢复项目状态。

### MVP Acceptance

输入：

> 一个小学生在暴雨夜发现校园秘密，悬疑但适合儿童，3 个镜头。

预期：

- App 本地生成项目。
- 有结构化角色、场景、分镜。
- 每个分镜有图片和视频。
- 不出现音色、TTS、试听、配音入口。
- 不生成单一合成 MP4。
- 播放页能顺序播放所有分镜视频。
- App 重启后项目状态仍可恢复。

## Main Risks

- Agnes 文本 JSON 输出不稳定：通过分步生成、schema 校验和 JSON 修复降低风险。
- 视频生成耗时长：用 Foreground WorkManager 和可恢复状态降低风险。
- 手机后台限制：必须设计恢复机制。
- 本地视频下载占空间：提供缓存管理和项目级删除。
- API Key 暴露风险：适合个人工具，不适合无信任边界的公开商业 App。
- 远程 URL 过期：优先下载媒体到本地，播放 fallback 到远程 URL。
