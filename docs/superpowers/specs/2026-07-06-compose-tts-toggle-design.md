# 视频合成阶段 TTS 开关设计

## 背景

当前视频合成阶段会根据分镜 `dialogue` 自动生成或复用 TTS 音频，然后用 FFmpeg 合成视频、音频和字幕。用户在 MiniMax 余额不足或只想快速合成预览视频时，需要能跳过 TTS 调用，但仍保留字幕烧录能力。

## 目标

- 只在视频合成阶段增加一个 TTS 开关。
- 开关默认开启，保持现有行为不变。
- 关闭开关后，单镜头合成和批量合成都不调用 TTS。
- 关闭开关后，如果分镜有对白，仍然生成并烧录字幕。
- 关闭开关后，输出视频无音频流。

## 非目标

- 不影响图片生成。
- 不影响视频生成。
- 不影响角色试听。
- 不影响单独的分镜 TTS 生成接口。
- 不影响音色分配。
- 不新增数据库字段。
- 不保存开关状态到剧集或用户配置。
- 不删除已有 `ttsAudioUrl` 或静态音频文件。

## 作用范围

开关只影响视频合成入口：

- 单个镜头合成：`POST /api/v1/compose/storyboards/:id/compose`
- 批量镜头合成：`POST /api/v1/compose/episodes/:id/compose-all`

不影响其他接口。

## 用户交互设计

在前端视频合成 tab 添加一个开关，默认开启：

```text
合成时包含 TTS 配音：开启 / 关闭
```

开关状态只在当前页面会话中生效。刷新页面后恢复默认开启。

## 行为规则

### 开关开启

保持现有合成逻辑：

```text
视频 + TTS 音频 + 字幕
```

当分镜有可配音对白时：

1. 优先复用已有 `ttsAudioUrl` 文件。
2. 如果没有可复用音频，则调用 TTS 生成音频。
3. 根据对白生成 SRT 字幕。
4. FFmpeg 合成视频、音频和字幕。

### 开关关闭

合成逻辑变为：

```text
视频 + 字幕
```

当分镜有可配音对白时：

1. 不复用已有 `ttsAudioUrl`。
2. 不调用 TTS。
3. 仍然根据对白生成 SRT 字幕。
4. FFmpeg 使用 `-an` 输出无音频视频。
5. 如果运行环境支持 FFmpeg `subtitles` filter，继续烧录字幕。

当分镜没有对白或对白属于环境音、BGM、无对白等可忽略内容时：

```text
直接合成无音频、无字幕视频
```

## 前端 API 设计

`composeAPI.shot` 和 `composeAPI.all` 增加可选 body 参数：

```ts
composeAPI.shot(id, { enable_tts: false })
composeAPI.all(epId, { enable_tts: false })
```

不传参数时等价于：

```ts
{ enable_tts: true }
```

## 后端 API 设计

单镜头合成请求体：

```json
{
  "enable_tts": false
}
```

批量合成请求体：

```json
{
  "enable_tts": false
}
```

后端兼容空 body 和旧调用。未传 `enable_tts` 时默认 `true`。

## 后端服务设计

`composeStoryboard` 增加 options 参数：

```ts
interface ComposeOptions {
  enableTTS?: boolean
}

composeStoryboard(storyboardId: number, options?: ComposeOptions)
```

内部行为：

```ts
const enableTTS = options.enableTTS ?? true
const hasDialogue = !parsedDialogue.ignorable
const shouldGenerateAudio = enableTTS && hasDialogue
const shouldGenerateSubtitle = hasDialogue
```

- `shouldGenerateAudio` 控制 TTS 复用和 TTS 生成。
- `shouldGenerateSubtitle` 只跟对白是否可用有关，不受 `enableTTS` 影响。
- FFmpeg 继续根据 `audioPath` 是否存在决定是否加入音频。

## 错误处理

- 开关开启时，TTS 失败仍然导致合成失败，保持现有行为。
- 开关关闭时，不调用 TTS，因此不会因为 TTS 余额不足或音色错误导致合成失败。
- 字幕 filter 不可用时，沿用现有行为：输出无字幕视频并记录日志。
- 视频文件缺失时，仍然报错。

## 涉及文件

预计修改：

- `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`
- `frontend/app/composables/useApi.ts`
- `backend/src/routes/compose.ts`
- `backend/src/services/ffmpeg-compose.ts`

不修改：

- 数据库 schema
- TTS adapter
- 图片生成服务
- 视频生成服务
- 单独分镜 TTS 路由

## 验收标准

- 默认进入合成 tab 时，TTS 开关为开启。
- 开关开启时，单镜头合成行为与现有逻辑一致。
- 开关开启时，批量合成行为与现有逻辑一致。
- 开关关闭时，单镜头合成不会调用 TTS。
- 开关关闭时，批量合成不会调用 TTS。
- 开关关闭且分镜有对白时，输出视频保留字幕但无音频。
- 开关关闭且分镜无对白时，输出视频无音频、无字幕。
- 不影响单独的 `POST /storyboards/:id/generate-tts`。
- 前端构建通过。
- 后端 TypeScript typecheck 通过。
