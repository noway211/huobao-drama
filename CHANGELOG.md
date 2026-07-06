# 2026-07-06 视频合成、字幕与 Agnes 图片生成改动记录

**日期**: 2026-07-06  
**分支**: dev  
**涉及文件**:
- `backend/src/services/ffmpeg-compose.ts`
- `backend/src/routes/compose.ts`
- `backend/src/services/adapters/agnesai-video.ts`
- `backend/src/services/adapters/agnesai-image.ts`
- `backend/src/services/adapters/registry.ts`
- `frontend/app/composables/useApi.ts`
- `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`

---

## 1. 视频合成阶段支持关闭 TTS

### 1.1 背景

MiniMax TTS 余额不足时，原合成流程会在内联生成 TTS 阶段失败，导致视频无法继续合成。实际业务需要在合成阶段允许跳过 TTS，但仍保留字幕烧录能力。

### 1.2 修复内容

- `composeStoryboard()` 新增 `ComposeOptions` 参数：
  - `enableTTS?: boolean`
  - 默认 `true`，兼容旧调用
- `enableTTS=false` 时：
  - 不复用已有 `ttsAudioUrl`
  - 不调用 `generateTTS()`
  - FFmpeg 输出无音频视频
  - 字幕仍按 `dialogue` 生成并烧录
- `POST /compose/storyboards/:id/compose` 和 `POST /compose/episodes/:id/compose-all` 支持请求体：
  - `{ "enable_tts": false }`
- 前端合成 tab 新增开关：
  - `合成时包含配音`
  - 默认勾选，取消后只影响合成阶段

### 1.3 验证

- `backend npm run typecheck` 通过
- `frontend npm run build` 通过
- 日志确认关闭 TTS 后批量合成不再出现 `AudioTask START tts-generate`

---

## 2. FFmpeg 中文字幕乱码修复

### 2.1 背景

关闭 TTS 后合成视频仍会烧录字幕，但字幕显示为方块/空白。排查发现 SRT 内容正确，FFmpeg `subtitles` filter 可用，问题出在默认字体不支持中文。

### 2.2 修复内容

- FFmpeg 字幕 `force_style` 增加中文字体：
  - `FontName=Heiti SC`
- 字幕样式保持：
  - 白色文字
  - 黑色描边
  - 20px 字号

### 2.3 验证

- 使用生成的 SRT 手动烧录测试视频，截图确认中文可正常显示
- `backend npm run typecheck` 通过

---

## 3. 导出页支持重新拼接

### 3.1 背景

导出面板已有拼接记录时，只展示视频预览和下载按钮，没有重新拼接入口。后端 `POST /merge/episodes/:id/merge` 本身支持重复创建新的拼接任务，因此问题是前端缺少入口。

### 3.2 修复内容

- 已有 `mergeUrl` 时，在导出栏新增 `重新拼接` 按钮
- 点击后复用现有 `doMerge()`，重新调用 `mergeAPI.merge(epId.value)`
- 保留原有 `下载视频` 按钮

### 3.3 验证

- `frontend npm run build` 通过

---

## 4. Agnes 视频生成补充中文语言提示

### 4.1 背景

Agnes 视频生成接口没有 `language` / `audio_language` / `voice` 等结构化音频语言参数，视频内语音语言只能通过 prompt 软约束。

### 4.2 修复内容

- Agnes 视频生成 adapter 在请求体 `prompt` 后追加：
  - `请使用中文对白与中文旁白。`
- 空 prompt 时使用该中文语言提示兜底

### 4.3 注意

该方式是 prompt 软约束，不是 Agnes API 的结构化语言控制参数，不能保证 100% 生效。

---

## 5. Agnes 图片生成支持官方图生图参数

### 5.1 背景

Agnes Image 2.0 Flash 官方文档要求图生图/参考图参数使用：

```json
{
  "extra_body": {
    "image": ["..."]
  }
}
```

原实现将 `agnesai` 图片生成挂在 `OpenAIImageAdapter` 上，使用的是 `content[].image_url` 格式，不符合 Agnes 官方文档。

### 5.2 修复内容

- 新增 `AgnesAIImageAdapter`
- 默认模型：
  - `agnes-image-2.0-flash`
- 请求接口：
  - `POST /v1/images/generations`
- 有参考图时构造：

```json
{
  "model": "agnes-image-2.0-flash",
  "prompt": "...",
  "size": "1024x768",
  "n": 1,
  "extra_body": {
    "image": ["https://... 或 data:image/...base64"],
    "response_format": "url"
  }
}
```

- `registry.ts` 中将：
  - `agnesai: new OpenAIImageAdapter()`
  - 改为 `agnesai: new AgnesAIImageAdapter()`

### 5.3 验证

- `backend npm run typecheck` 通过

---

# Agnes 视频生成接口修复记录

**日期**: 2026-07-05  
**分支**: dev  
**涉及文件**: `backend/src/services/adapters/agnesai-video.ts`

---

## 1. 问题诊断

### 1.1 视频生成任务长期 processing / 参考图不生效

**现象**: `reference_mode=first_last` 的视频任务（id=47, 48）长时间停留在 `processing`，日志中大量 `poll-retry error=fetch failed`；即便生成，首帧/尾帧参考图也未生效。

**根因分析**（对照 [Agnes 官方文档](https://agnes-ai.com/zh-Hans/docs/agnes-video-v20)）:

| 参数 | 旧实现（错误） | 文档规范 |
|---|---|---|
| 尺寸 | `size: "1280x768"` | `width` / `height`（默认 1152/768） |
| 时长 | `seconds: "10"` | `num_frames`（≤441 且 8n+1）+ `frame_rate` |
| 首尾帧 | **完全未传** | `mode: "keyframes"` + `extra_body.image: [首帧, 尾帧]` |
| 单图 | `first_frame`（臆造字段） | `image` + `mode: "ti2vid"` |

- `buildGenerateRequest` 从未把 `firstFrameUrl` / `lastFrameUrl` 写进请求体，参考图静默失效
- 时长与尺寸字段名均与接口不符，接口按默认值生成
- `parsePollResponse` 完成分支仅取 `remixed_from_video_id`，缺少兜底字段

> 注：轮询期间的 `fetch failed` 主要来自 Agnes 接口间歇性超时，代码重试逻辑本身正常。

---

## 2. 修复内容

### 2.1 请求体对齐接口规范（agnesai-video.ts）

- 尺寸改用 `width`/`height`，新增 `parseSize()` 解析 `"宽x高"`，默认 `1152x768`
- 时长改用 `num_frames` + `frame_rate`（24fps），新增 `durationToNumFrames()` 按 8n+1、≤441 规则换算（5s→121 帧、10s→241 帧）
- `first_last` 模式改用 `mode: "keyframes"` + `extra_body.image: [首帧, 尾帧]`
- `single` 模式改用 `image` + `mode: "ti2vid"`
- 新增 `multiple` 模式支持 `extra_body.image` 数组

### 2.2 完成响应取值兜底（agnesai-video.ts）

`parsePollResponse` / `extractVideoUrl` 的下载地址取值改为 `remixed_from_video_id || video_url || url`，保持以 `remixed_from_video_id` 为主。

---

# 宫格图生成修复记录

**日期**: 2026-06-27  
**分支**: dev  
**涉及文件**: `backend/src/routes/grid.ts`, `backend/src/agents/tools/grid-prompt-tools.ts`, `backend/src/services/image-generation.ts`, `backend/src/services/adapters/registry.ts`, `backend/src/services/adapters/openai-image.ts`, `backend/src/utils/task-logger.ts`

---

## 1. 问题诊断

### 1.1 宫格图生成失败（fetch failed）

**现象**: 宫格图生成请求（ImageTask id=58, 59）连续两次失败，错误为 `fetch failed`，而角色图片生成（id=52~57）全部成功。

**根因分析**:

| | 角色图片 ✅ | 宫格图 ❌ |
|---|---|---|
| **尺寸** | `1920x1080` | `2880x1620` |
| **prompt 长度** | ~100 字 | ~1000+ 字 |

- Agnes AI `agnes-image-2.0-flash` 对 `2880×1620` 大尺寸 + 超长中文 prompt 组合会直接断开 TCP 连接（表现为 `fetch failed`），而非返回 HTTP 错误码
- 这是服务端网关层的隐性限制

### 1.2 first_last 模式行内重复

**现象**: 2×2 宫格图每行提示语相同。

**根因**: 按格子索引 `i` 线性分配镜头，`i % storyboards.length` 导致同一镜头在上下行重复出现。

---

## 2. 修复内容

### 2.1 尺寸限制（grid.ts）

**修改前**:
```typescript
const cellW = 960, cellH = 540
const actualCols = cols
const actualRows = rows
const size = `${cellW * actualCols}x${cellH * actualRows}`
```

**修改后**:
```typescript
// 限制总尺寸不超过 1920x1080，避免 Agnes AI 对大图直接断连
const maxW = 1920, maxH = 1080
const actualCols = cols
const actualRows = rows
const cellW = Math.floor(maxW / actualCols)
const cellH = Math.floor(maxH / actualRows)
const size = `${cellW * actualCols}x${cellH * actualRows}`
```

- 3×3 宫格图从 `2880x1620` 降为 `1920x1080`
- 2×2 宫格图从 `1920x1080` 保持 `1920x1080`

### 2.2 first_last 模式按行分配镜头（grid.ts）

**修改前**:
```typescript
const sb = storyboards[i % storyboards.length]
const isFirst = i % 2 === 0
```

**修改后**:
```typescript
const row = Math.floor(i / cols)
const col = i % cols
const sb = storyboards[row % storyboards.length]
const isFirst = col % 2 === 0
```

**分配逻辑变更**:

| 模式 | 修复前 | 修复后 |
|---|---|---|
| 2×2 + 2 镜头 | 格1=镜头1首帧, 格2=镜头2尾帧, 格3=镜头1首帧, 格4=镜头2尾帧 | 格1=镜头1首帧, 格2=镜头1尾帧, 格3=镜头2首帧, 格4=镜头2尾帧 |

- 每行一个镜头，左列首帧，右列尾帧

### 2.3 first_frame 模式循环填满格子（grid.ts）

**修改前**:
```typescript
const cells = storyboards.map((sb, i) => { ... })
```

**修改后**:
```typescript
const totalCells = rows * cols
const cells = Array.from({ length: totalCells }, (_, i) => {
  const sb = storyboards[i % storyboards.length]
  ...
})
```

- 避免 3×3/4×4 选镜头数 < 格子数时缺格

### 2.4 Prompt 精简与英文化（grid.ts + grid-prompt-tools.ts）

**修改内容**:
- 中文标注（`参考`、`格1`、`首帧`）→ 英文（`ref`、`Cell 1`、`first frame`）
- 移除 `buildStoryboardReferenceHints` 在 cell prompt 中的重复注入
- 简化句式，去除冗余描述

**示例**:
- 修复前: `格1（row 1 col 1）：参考图片1（北寒风角色），dusk, old man...`
- 修复后: `Cell 1 (row 1 col 1): dusk, old man...`

### 2.5 风格提示词注入（grid.ts + grid-prompt-tools.ts）

**新增**:
```typescript
import { getStylePrompt } from '../services/adapters/style-prompt.js'
const style = getStylePrompt(dramaStyle) || 'cinematic lighting, film grain, dramatic composition'
```

- `grid.ts` 的 `buildGridPrompt` 使用 `getStylePrompt` 将 drama.style 转为英文提示词
- `grid-prompt-tools.ts` 的角色/场景提示词生成也注入风格提示词

### 2.6 增强 fetch 错误日志（image-generation.ts）

**修改前**:
```typescript
const cause = (fetchErr as any).cause
const detail = cause ? `${cause.name}: ${cause.message}` : fetchErr.message
throw new Error(`Fetch failed: ${detail}`)
```

**修改后**:
```typescript
const cause = (fetchErr as any).cause
const detail = cause
  ? `${cause.name}: ${cause.message} (code=${cause.code || 'N/A'})`
  : `${fetchErr.message} (type=${fetchErr.type || 'N/A'})`
const full = fetchErr.stack ? `${detail}\n${fetchErr.stack}` : detail
throw new Error(`Fetch failed: ${full}`)
```

- 记录 `cause.code` 和完整 stack trace，便于诊断 `fetch failed`

### 2.7 日志写入文件（task-logger.ts）

**新增**:
```typescript
const LOG_DIR = process.env.LOG_DIR || path.resolve(__dirname, '../../../data/logs')
fs.mkdirSync(LOG_DIR, { recursive: true })

function writeToFile(rawLine: string) {
  try {
    const today = new Date().toISOString().slice(0, 10)
    const filePath = path.join(LOG_DIR, `${today}.log`)
    fs.appendFileSync(filePath, rawLine + '\n', 'utf-8')
  } catch {
    // 文件写入失败时静默忽略，不影响主流程
  }
}
```

- 所有 `logTask` / `logTaskPayload` 输出同时写入 `data/logs/YYYY-MM-DD.log`

### 2.8 Provider Adapter 注册表更新（registry.ts）

**修改**:
- 新增 `agnesai: new OpenAIImageAdapter()` 图片适配器
- 新增 `agnesai: new AgnesAIVideoAdapter()` 视频适配器
- 内联 `OpenAIVideoAdapter` 实现（替换外部引用）

### 2.9 OpenAI Image Adapter 移除 response_format（openai-image.ts）

**修改**:
```typescript
// 移除: response_format: 'url'
```

- 部分 provider 不支持该字段，导致请求失败

---

## 3. 文件变更清单

| 文件 | 变更类型 | 变更说明 |
|---|---|---|
| `backend/src/routes/grid.ts` | 修改 | 尺寸限制、按行分配、prompt精简、风格注入 |
| `backend/src/agents/tools/grid-prompt-tools.ts` | 修改 | 按行分配、prompt英文化、风格注入 |
| `backend/src/services/image-generation.ts` | 修改 | 增强fetch错误日志 |
| `backend/src/services/adapters/registry.ts` | 修改 | 新增agnesai适配器、内联OpenAI视频适配器 |
| `backend/src/services/adapters/openai-image.ts` | 修改 | 移除response_format字段 |
| `backend/src/services/adapters/types.ts` | 修改 | VideoGenerationRecord添加size字段 |
| `backend/src/utils/task-logger.ts` | 修改 | 日志同时写入文件 |

---

## 4. 测试建议

1. **2×2 first_last 模式**: 选 2 个镜头，验证每行不同镜头，左首帧右尾帧
2. **3×3 first_frame 模式**: 选 3 个镜头，验证 9 格循环填满，尺寸为 1920x1080
3. **4×4 first_last 模式**: 选 4 个镜头，验证 16 格按行分配
4. **错误日志**: 故意触发失败（如断网），验证日志写入 `data/logs/2026-06-27.log`

---

## 3. 新增修复（2026-06-27 后续）

### 3.1 TCP 连接超时延长（image-generation.ts）

**问题**: `AbortSignal.timeout(600_000)` 只控制请求总超时，但 undici 默认 TCP 连接超时只有 10s，网络波动时直接 `ConnectTimeoutError`。

**修复**:
```typescript
import { Agent, fetch as undiciFetch } from 'undici'
const fetchAgent = new Agent({ connect: { timeout: 60_000 } })

resp = await undiciFetch(url, {
  ...
  signal: AbortSignal.timeout(600_000),
  dispatcher: fetchAgent,
})
```

- 连接超时从 10s → **60s**
- 总请求超时保持 600s

### 3.2 cell prompt 风格提示词注入（grid.ts + grid-prompt-tools.ts）

**问题**: 只在整体 grid prompt 注入 style，cell prompt 未注入。

**修复**:
- `buildGridCellPrompts()` 增加 `dramaStyle` 参数
- 每个 cell prompt 末尾添加 `, ${style}`
- `grid-prompt-tools.ts` 同样为每个 cell prompt 添加 style

### 3.3 ECONNRESET 修复 — 正确传递参考图（openai-image.ts）

**问题**: 宫格图收集 5 张参考图，但 `OpenAIImageAdapter` 之前忽略 `referenceImages`，参考图没有正确传递 → 导致多个 base64 data URL 塞入请求体 → 请求体过大 → Agnes AI 网关主动断开 (`ECONNRESET`)。

**修复**: 使用 OpenAI multi-modal `content` 数组格式正确传递参考图：
```typescript
if (record.referenceImages) {
  const refs: string[] = JSON.parse(record.referenceImages)
  const content = []
  content.push({ type: 'text', text: record.prompt })
  for (const ref of refs) {
    content.push({ type: 'image_url', image_url: { url: ref } })
  }
  body = { model, content, ... }
}
```

- 参考图已经过压缩，直接传递 data URL
- 格式符合 OpenAI 兼容 API 规范，Agnes AI 支持

### 3.4 参考图压缩参数调整（storage.ts）

**问题**: 参考图压缩后仍然较大，需要进一步减小。

**调整**:
| 参数 | 修改前 | 修改后 |
|---|---|---|
| maxWidth/maxHeight | 768px | **500px** |
| quality | 68% | **50%** |

- 5 张参考图总大小从 ~2.5MB → ~100~200KB
- 减少请求体大小，避免网关断开

---

## 4. 文件变更清单（新增）

| 文件 | 变更类型 | 变更说明 |
|---|---|---|
| `backend/src/services/image-generation.ts` | 修改 | 自定义 undici Agent，连接超时 60s |
| `backend/src/services/adapters/openai-image.ts` | 修改 | 正确处理 referenceImages，使用 content 数组格式 |
| `backend/src/routes/grid.ts` | 修改 | buildGridCellPrompts 增加 dramaStyle 参数，cell prompt 注入 style |
| `backend/src/agents/tools/grid-prompt-tools.ts` | 修改 | generateGridPrompt 读取 drama style，cell prompt 注入 style |
| `backend/src/utils/storage.ts` | 修改 | 调整参考图压缩参数：500px 50% |

---

---

## 4. 新增修复（2026-06-27 重试 + 超时延长）

### 4.1 TCP 连接超时延长

**问题**: 用户要求连接超时从 60s → 90s。

**修改**:
```typescript
// 自定义 undici Agent：连接超时 90s，避免默认 10s 连接超时
const fetchAgent = new Agent({ connect: { timeout: 90_000 } })
```

### 4.2 生成失败重试支持

**问题**: 当前宫格图生成失败后，UI 完全重置到第一步，用户必须重新选择镜头 → 重新生成提示词 → 重新提交生成。需要保留状态 + 重试按钮。

**后端修改** (`backend/src/routes/grid.ts`):
- 新增 `POST /grid/retry` 端点
- 输入: `{ image_generation_id: number }`
- 输出: `{ image_generation_id: number, grid?: { rows, cols } }`
- 逻辑: 读取已有失败记录 → 提取所有参数 → 创建新的生成 → 返回新 ID

**前端修改** (`frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`):
- 新增 `gridFailed` ref 标记失败状态
- 生成失败 / 请求失败不再 `gridStep = 0`，保持在 step 2
- UI 显示错误信息 + **"重新生成"** 按钮 + "上一步" 按钮
- 新增 `retryGridGen()` 函数调用 `/grid/retry` API 并重启轮询
- `useApi.ts` 新增 `gridAPI.retry()` 方法

### 4.3 修复 retry 类型错误 (`backend/src/routes/grid.ts`)

- `record.referenceImages` 是 JSON 字符串，需要 parse 为 `string[]` 后传给 `generateImage()`

---

## 5. 文件变更清单（新增）

| 文件 | 变更类型 | 变更说明 |
|---|---|---|
| `backend/src/services/image-generation.ts` | 修改 | connect timeout: 60s → 90s |
| `backend/src/routes/grid.ts` | 新增端点 | 新增 `POST /grid/retry` |
| `frontend/app/composables/useApi.ts` | 修改 | 新增 `gridAPI.retry` |
| `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue` | 修改 | 新增 retry 状态和 UI，preserve state on failure |

## 6. 测试建议

1. **重试流程测试**:
   - 触发一次生成失败（网络问题/upstream error）
   - 验证 UI 显示错误 + 重试按钮（不重置到第一步）
   - 点击重试 → 验证重新提交，重启轮询
   - 成功 → 验证进入预览
   - 失败 → 验证仍然显示重试按钮

2. **上一步测试**:
   - 点击"上一步（修改提示词）" → 验证回到 prompt 编辑 step 1

---

---

## 5. 新增修复（2026-06-27 运行时修复）

### 5.1 请求体大小日志记录（image-generation.ts）

**修改**: 在 `processImageGeneration` 中添加 `bodySizeKB` 日志：
```typescript
const bodyStr = JSON.stringify(body)
const bodySizeKB = Math.round(Buffer.byteLength(bodyStr, 'utf8') / 1024)
logTaskProgress('ImageTask', 'request', { id, bodySizeKB, ... })
```

- 便于诊断请求体是否过大导致 upstream 错误

### 5.2 前端 TypeScript 语法修复

**修复 1**: `as any` 语法在 Vue SFC 中不可用
```typescript
// 修复前
toast.error(String((e as any).message))
// 修复后
const msg = (e && (e).message) ? (e).message : String(e)
toast.error(msg)
```

**修复 2**: `<script setup>` 缺少 `lang="ts"`
```html
<!-- 修复前 -->
<script setup>
<!-- 修复后 -->
<script setup lang="ts">
```

- Vue 编译器将 `<script setup>` 默认当 JS 处理，遇到 `ref<number|null>(null)` 报错 `number is not defined`
- 添加 `lang="ts"` 后 TypeScript 语法正常解析

### 5.3 前端端口说明

- 前端开发服务器默认尝试 3013 端口
- 若 3013 被占用，自动切换到 3002/3003 等可用端口
- 实际访问地址以终端输出为准

---

## 6. 文件变更清单（本次新增）

| 文件 | 变更类型 | 变更说明 |
|---|---|---|
| `backend/src/services/image-generation.ts` | 修改 | 新增 `bodySizeKB` 日志 |
| `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue` | 修改 | `<script setup>` → `<script setup lang="ts">` |
| `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue` | 修改 | 移除 `as any` TypeScript 语法 |

## 7. 相关提交

- 修复宫格图尺寸和 prompt 问题
- 修复 first_last 模式按行分配镜头
- 修复连接超时、参考图传递、压缩参数
- 新增重试按钮 + 延长连接超时
- 修复 Vue TypeScript 编译错误
