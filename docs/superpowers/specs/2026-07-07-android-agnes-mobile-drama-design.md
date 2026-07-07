# Android 端 Agnes 短剧生成实现计划

## Context

用户希望参考当前 `huobao-drama` 工程，在 Android 手机端独立实现短剧生成能力。新的约束是：

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
- Room 保存项目、角色、场景、分镜、图片任务、视频任务。
- EncryptedSharedPreferences/Android Keystore 保存用户手动输入的 Agnes API Key。
- WorkManager 或 ForegroundService 执行长耗时生成任务。
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

1. 用户设置 Agnes API Key。
2. 用户输入短剧主题、风格、镜头数、画幅、单镜头时长。
3. App 调 Agnes 文本模型生成结构化短剧数据。
4. App 生成角色、场景、分镜。
5. App 为每个分镜调用 Agnes 图片接口生成图片。
6. App 为每个分镜调用 Agnes 视频接口生成视频。
7. App 本地保存生成记录和媒体 URL/文件。
8. App 用列表和播放器按顺序播放分镜视频。

MVP 的“短剧成片”表现形式是：分镜视频列表 + 连续播放队列。不是单一合成 MP4 文件。

## Agnes API Usage

### Common

- Base URL: `https://apihub.agnes-ai.com`
- Auth: `Authorization: Bearer {userApiKey}`
- API Key 由用户在设置页输入。
- App 本地加密保存 API Key，但必须提示：手机端保存 key 不能达到服务端级别安全，适合个人工具/内测，不适合公开分发给不可信用户。

### Text Generation

使用 OpenAI-compatible chat completions：

- `POST /v1/chat/completions`
- 用于生成结构化 JSON：剧本、角色、场景、分镜。
- Android 不实现 Mastra agent runtime。
- 采用“强约束 prompt + JSON schema 文本说明 + 本地 JSON 解析/修复”的方式。

建议分 2 步，不要一次生成所有内容：

1. `generateDramaStructure`
   - 输入：主题、风格、镜头数、画幅、时长。
   - 输出：标题、简介、角色、场景。
2. `generateStoryboards`
   - 输入：标题、简介、角色、场景、镜头数。
   - 输出：分镜数组，每个分镜包含 `title`、`description`、`sceneName`、`characters`、`imagePrompt`、`videoPrompt`、`durationSeconds`。

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

MVP 优先只做文生图，生成每个分镜首帧图。

### Video Generation

参考当前后端：`backend/src/services/adapters/agnesai-video.ts`

- `POST /v1/videos`
- 单图生视频：用分镜图片作为参考图。
- `num_frames` 需要满足 Agnes 限制：小于等于 441，并满足 `8n + 1`。
- `frame_rate` 建议固定 24。
- 按画幅换算 `width/height`。
- 生成后轮询：`GET /v1/videos/{taskId}`。

MVP 每个分镜生成一个视频，不做本地拼接。

## Limited Skill System

Android 端需要保留“skill”概念，但必须是受限能力，不复制当前后端/Claude Code 式 skill 运行时。

### Skill Scope

允许：

- 本地内置 skill 定义。
- 用户在 App 内启用/禁用内置 skill。
- Prompt 模板变量替换。
- 调 Agnes chat completions。
- 要求模型输出固定 JSON。
- 本地解析 JSON 并写入 Room。
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

### Built-in Skills

Android 端需要覆盖完整短剧生成链路，MVP 内置以下受限 skill：

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
  - 用途：生成多个标题候选。
  - 输出：标题数组。
- `style_preset_generator`
  - 用途：根据用户输入生成视觉风格预设。
  - 输出：风格 preset。
- `localized_copywriter`
  - 用途：生成项目介绍、分享文案。
  - 输出：短文案数组。

首版必须支持 Core Generation Skills、Prompt Refinement Skills 和 Utility Skills。Optional Post-MVP Skills 可以先只保留定义，不接入主流程。

### Skill Definition Format

Skill 可以以 JSON 或 Kotlin data class 表示，首版建议内置在 assets 或代码常量中：

```json
{
  "id": "storyboard_breaker",
  "name": "分镜拆解",
  "version": 1,
  "enabled": true,
  "model": "agnes-chat-model",
  "temperature": 0.6,
  "input_schema": {
    "title": "string",
    "characters": "array",
    "scenes": "array",
    "shot_count": "number"
  },
  "output_schema": {
    "storyboards": "array"
  },
  "prompt_template": "..."
}
```

### Skill Runtime

新增本地 `SkillEngine`：

1. 根据 skill id 读取内置定义。
2. 校验输入字段完整性。
3. 用变量替换生成 prompt。
4. 调 Agnes chat completions。
5. 提取 JSON。
6. 校验必填字段。
7. 失败时调用 `json_repair` 一次。
8. 返回 typed result 给 usecase。

`SkillEngine` 不直接操作 UI，不直接操作网络以外的系统资源；写库由 repository/usecase 完成。

### Skill Storage

Room 增加：

- `SkillConfigEntity`
  - `id`
  - `version`
  - `enabled`
  - `temperatureOverride?`
  - `updatedAt`

首版只保存启用状态和少量参数，不支持用户编辑完整 prompt。后续可以增加“高级模式”让用户编辑 prompt，但仍不允许工具调用或代码执行。

### Safety And Debugging

- skill 调用日志只记录 skill id、耗时、状态、错误摘要。
- 不记录 API Key。
- 不完整记录用户剧本文本，避免日志过大或隐私泄露。
- 调试页可以显示最近一次模型原始输出，但需要用户主动打开。
- 所有 skill 输出必须经过 JSON 解析和字段校验，不能把模型文本直接当业务数据写入。

## Android App Architecture

### Modules / Packages

可以先做单 App module，按 package 分层：

- `data.local`
  - Room database、DAO、entities。
- `data.remote`
  - Retrofit services、OkHttp interceptors、Agnes request/response DTO。
- `data.repository`
  - DramaRepository、GenerationRepository。
- `domain.model`
  - App 内部业务模型。
- `domain.usecase`
  - CreateDramaUseCase、GenerateImagesUseCase、GenerateVideosUseCase、RetryStoryboardUseCase。
- `skill`
  - BuiltInSkillRegistry、SkillEngine、SkillInputValidator、SkillJsonParser。
- `worker`
  - WorkManager workers 或 ForegroundService。
- `ui.settings`
  - API Key 设置页。
- `ui.create`
  - 短剧创建页。
- `ui.project`
  - 项目详情/进度页。
- `ui.storyboard`
  - 分镜详情页。
- `ui.player`
  - 连续播放页。

### UI Technology

不用 Jetpack Compose。

使用：

- XML layout。
- ViewBinding。
- RecyclerView + ListAdapter。
- Material Components。
- Fragment 或 Activity + Navigation Component。
- Media3 PlayerView 播放视频。

## Data Model

Room entities：

### `ProjectEntity`

- `id`
- `title`
- `prompt`
- `style`
- `aspectRatio`
- `shotCount`
- `shotDurationSeconds`
- `status`
- `createdAt`
- `updatedAt`

### `CharacterEntity`

- `id`
- `projectId`
- `name`
- `description`
- `appearance`

### `SceneEntity`

- `id`
- `projectId`
- `name`
- `description`

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
- `updatedAt`

### Status Values

- `pending`
- `processing`
- `completed`
- `failed`
- `cancelled`

## Generation Flow

### 1. API Key Setup

- 用户进入设置页。
- 输入 Agnes API Key。
- App 调一个轻量请求验证 key 是否可用。
- 验证通过后写入 EncryptedSharedPreferences。

### 2. Create Project

- 用户输入主题、风格、镜头数、画幅、时长。
- 写入 `ProjectEntity(status=processing)`。
- 启动 WorkManager/ForegroundService。

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

- JSON 解析失败时，最多用一次“修复 JSON”prompt。
- 仍失败则项目进入 failed，展示原始错误。

### 4. Image Generation

按分镜顺序或有限并发执行：

- 建议并发数：1 或 2。
- 调 Agnes image generation。
- 如果同步返回 URL，保存 `imageUrl`。
- 如果返回 task id，则轮询 task。
- 可选：下载图片到 app-specific storage。
- 更新 `imageStatus`。

### 5. Video Generation

图片完成后执行：

- 用 `imageUrl` 或本地图片上传/转 data URI 的方式作为参考图。
- MVP 优先使用 Agnes 可访问的 URL；如果只有本地文件，需要转 data URI，注意体积压缩。
- 调 Agnes video generation。
- 保存 `videoTaskId`。
- 轮询完成后保存 `videoUrl`。
- 可选下载视频到 app-specific storage。
- 更新 `videoStatus`。

### 6. Playback

- 不做 compose/merge。
- 项目详情页展示每个分镜的视频卡片。
- 播放页用 Media3 按顺序播放 `videoUrl` 或 `localVideoPath`。
- 支持上一段/下一段。

## Storage And Downloads

MVP 可以先只保存远程 URL，降低复杂度。

增强版再支持下载：

- 图片保存到 `context.filesDir/images/`。
- 视频保存到 `context.filesDir/videos/`。
- 用 DownloadManager 或 OkHttp streaming download。
- Room 保存本地路径。

如果视频 URL 有过期风险，应优先下载视频。

## Background Execution

短剧生成耗时长，不能依赖 Activity 生命周期。

推荐：

- MVP：WorkManager + ForegroundInfo。
- 生成中显示通知。
- 用户退出 App 后任务可继续。
- 网络断开时暂停/失败并允许重试。

注意：

- 很长的视频生成任务可能超过 WorkManager 的舒适范围。
- 如果 Android 系统杀进程，需要下次打开 App 后根据 Room 状态恢复轮询。

## Retry Strategy

粒度：

- 重试文本结构生成。
- 重试单个分镜图片。
- 重试单个分镜视频。

不做：

- 自动无限重试。
- 全局 silent retry。

建议：

- 网络错误重试 1 次。
- API 错误先调用 `generation_failure_analyzer` 分析是否可重试。
- 如果失败原因与内容安全、prompt 过长或表达不清有关，调用 `content_safety_rewriter` 生成新的 prompt 候选。
- 用户手动确认后重试，不自动无限重试。

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
2. 实现设置页：输入、验证、保存、删除 Agnes API Key。
3. 实现 Agnes API client：chat、image generation、image task poll、video generation、video poll。
4. 实现受限 skill 基础设施：BuiltInSkillRegistry、SkillEngine、输入校验、JSON 解析/修复。
5. 实现 Room entities/DAO/repository，包括 SkillConfigEntity。
6. 实现创建项目页和项目详情页。
7. 实现文本结构生成 worker/usecase，统一通过 SkillEngine 调内置 skill。
8. 实现图片生成 worker/usecase。
9. 实现视频生成 worker/usecase。
10. 实现进度 UI、失败展示、单分镜重试。
11. 实现 Media3 连续播放页。
12. 真机验证完整流程。

## Verification Plan

### Unit / Local Tests

- JSON 解析：角色/场景/分镜结构化输出。
- SkillEngine：输入校验、模板变量替换、输出字段校验、JSON 修复重试。
- 内置 skill 覆盖检查：`idea_expander`、`drama_structure_generator`、`character_designer`、`scene_designer`、`storyboard_breaker`、`image_prompt_refiner`、`video_prompt_refiner`、`continuity_checker`、`json_repair`、`content_safety_rewriter`、`generation_failure_analyzer` 都有定义、schema 和测试样例。
- SkillConfigEntity：启用/禁用内置 skill 后流程行为正确；必需 skill 被禁用时主流程给出明确错误。
- `num_frames` 计算满足 `8n + 1` 和 `<=441`。
- Agnes request DTO 序列化正确。
- Room status 转换正确。
- 日志不包含 Agnes API Key 明文。

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

## Main Risks

- Agnes 文本 JSON 输出不稳定：通过分步生成和 JSON 修复降低风险。
- 视频生成耗时长：用 Foreground WorkManager 和可恢复状态降低风险。
- 手机后台限制：必须设计恢复机制。
- 本地视频下载占空间：MVP 先保存 URL，后续加下载管理和清理。
- API Key 暴露风险：适合个人工具，不适合无信任边界的公开商业 App。
