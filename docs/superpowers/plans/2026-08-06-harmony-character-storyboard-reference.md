# 鸿蒙端角色提取与分镜图片角色依赖

**日期**: 2026-08-06
**状态**: 已实现

## Context

鸿蒙端当前完全没有角色管理功能——没有角色模型、没有角色提取、没有角色图片生成。分镜图片生成时只传 `imagePrompt` 文本，不传角色参考图，导致同一角色在不同分镜中形象不一致，合成视频后角色变来变去。

本计划参照后端 Web 版已有的角色提取和参考图机制，在鸿蒙端补齐这一能力。

## 改动文件清单（按层从上到下）

| 文件 | 改动类型 |
|------|----------|
| `model/DramaModels.ets` | 修改 — 新增 Character 接口和 CharacterAssetStatus 等类型 |
| `data/DramaDatabase.ets` | 修改 — 新增 characters 表、storyboards 表新增 character_ids 列 |
| `data/CharacterLocalDataSource.ets` | **新增** — 角色 CRUD |
| `data/DramaRepository.ets` | 修改 — 代理 CharacterLocalDataSource |
| `data/StoryboardLocalDataSource.ets` | 修改 — mapRow/replaceStoryboards 包含 character_ids |
| `remote/AgnesImageRepository.ets` | 修改 — 支持 referenceImages 参数（extra_body.image） |
| `remote/AgnesStoryboardRepository.ets` | 修改 — system prompt 增加 character_names，解析存入 characterIds |
| `remote/AgnesTextRepository.ets` | 修改 — postChat 改为 public |
| `data/MediaDownloadRepository.ets` | 修改 — 新增 downloadCharImage |
| `usecase/UseCases.ets` | 修改 — 新增角色提取、角色图片生成、分镜参考图注入 |
| `pages/ProjectDetailPage.ets` | 修改 — 新增「提取角色」和「生成角色图」按钮 |

## 详细实现步骤

### Step 1: 数据模型 — `model/DramaModels.ets`

新增 Character 接口：

```typescript
export interface Character {
  id: number;
  projectId: number;
  episodeId: number | null;
  name: string;
  role: string;          // 主角/配角/路人
  description: string;
  appearance: string;     // 外貌描述（用于生成图片的 prompt）
  personality: string;
  imageStatus: AssetStatus;
  imageUrl: string | null;
  imageLocalPath: string | null;
  imageErrorMessage: string | null;
  createdAt: number;
  updatedAt: number;
}
```

StoryboardShot 接口新增字段：`characterIds: string | null`（JSON 数组字符串，如 `"[1,3,5]"`）。

复用已有的 `AssetStatus` 枚举。

### Step 2: 数据库 — `data/DramaDatabase.ets`

**2a. 新增 `characters` 表**

**2b. `storyboards` 表新增 `character_ids TEXT` 列**

用 `addColumnIfMissing()` 通过 `PRAGMA table_info` 先查列是否存在再 ALTER TABLE，兼容已有数据库。

### Step 3: 角色数据源 — `data/CharacterLocalDataSource.ets`（新增）

参照 `StoryboardLocalDataSource.ets` 的模式实现：
- `replaceCharacters(projectId, characters)` — 全量替换
- `getCharacters(projectId)` — 按 projectId 查询
- `updateCharacterImage(...)` — 更新角色图片生成结果
- `deleteCharactersForProject(projectId)` — 级联删除

### Step 4: Repository Facade — `data/DramaRepository.ets`

新增代理方法：
- `replaceCharacters(projectId, characters)`
- `getCharacters(projectId)`
- `updateCharacterImage(characterId, ...)`
- `deleteCharactersForProject(projectId)`

同时在 `deleteProject()` 中增加删除角色数据的调用。

### Step 5: 图片生成支持参考图 — `remote/AgnesImageRepository.ets`

根据 Agnes AI 图生图 API 文档确认：参考图通过 `extra_body.image` 数组传入（支持 URL 和 data URI base64），API 无 `role` 标签字段，角色关联完全靠 prompt 文字描述。

修改 `generateImage` 方法签名，增加可选参数 `referenceImages?: string[]`：

```typescript
async generateImage(
  settings: AgnesSettings,
  prompt: string,
  referenceImages?: string[]
): Promise<TextResult>
```

参数从 `shot: StoryboardShot` 改为 `prompt: string`，因为角色图生成不需要 StoryboardShot 对象。

### Step 6: 用例层 — `usecase/UseCases.ets`

**6a. 角色提取（新增方法）：**

`static async extractCharacters(projectId, settings)` — 从剧本中提取角色：
1. 获取项目剧本（`episode.scriptContent ?? project.generatedScript`）
2. 将剧本发送给 LLM（复用 `AgnesTextRepository.postChat`），使用角色提取 system prompt
3. 解析返回的 JSON 数组为 Character 列表
4. 存入数据库（`replaceCharacters`）

System prompt:
```
你是一个短剧角色提取专家。从剧本中提取所有角色信息。
返回 JSON 数组，每个条目包含：name、role、description、appearance、personality。
只返回 JSON 数组。
```

**6b. 角色图片生成（新增方法）：**

`static async generateCharacterImages(projectId, settings, onProgress?)` — 为每个角色生成立绘

**6c. 分镜图片生成时传角色参考图（修改 `generateStoryboardImages`）：**

`buildCharacterReferences` 方法：
1. 解析 `storyboard.characterIds`（兼容数字 ID 数组和角色名字符串数组）
2. 收集角色的 `imageLocalPath` 或 `imageUrl` 作为参考图列表（最多 3 个）
3. **Prompt 增强**：在分镜 `imagePrompt` 前面追加角色描述信息
4. 调用 `generateImage(settings, enrichedPrompt, referenceImages)`

**6d. 角色名字匹配到数据库 ID：**

`remapCharacterNamesToIds(projectId)` — 分镜生成后将 LLM 返回的角色名匹配到数据库 ID（目前仅记录日志）。

### Step 7: UI — `pages/ProjectDetailPage.ets`

新增状态变量：`characters`、`hasCharacters`、`hasCharacterImages`

新增两个按钮（放在分镜和图片生成之间）：
1. **「提取角色」按钮** — 调用 `UseCases.extractCharacters()`
2. **「生成角色图」按钮** — 调用 `UseCases.generateCharacterImages()`

新增角色卡片区域：横向滚动，显示角色缩略图和名字/角色。

## 数据流

```
脚本生成 → 分镜生成 → [提取角色] → [生成角色图] → 生成图片（带角色参考图）→ 生成视频 → 合成成片
```

关键逻辑：
1. **分镜生成时** LLM 返回 `character_names`（如 `["张三", "李四"]`），存入 `storyboards.character_ids`
2. **角色提取时** `extractCharacters` 解析剧本提取角色列表，存入 `characters` 表
3. **角色图生成时** `generateCharacterImages` 为每个角色调用 `v1/images/generations` 生成立绘
4. **分镜图片生成时** `buildCharacterReferences` 收集角色图片作为 `extra_body.image` 参考图，并在 prompt 前追加角色外貌描述，调用 Agnes AI 图生图 API 保持角色形象一致

## 实现顺序

1. `model/DramaModels.ets` — Character 接口
2. `data/DramaDatabase.ets` — characters 表 + storyboards 加列
3. `data/CharacterLocalDataSource.ets` — CRUD（新增）
4. `data/DramaRepository.ets` — 代理
5. `data/StoryboardLocalDataSource.ets` — character_ids 列
6. `remote/AgnesImageRepository.ets` — referenceImages
7. `remote/AgnesStoryboardRepository.ets` — character_names
8. `remote/AgnesTextRepository.ets` — postChat public
9. `data/MediaDownloadRepository.ets` — downloadCharImage
10. `usecase/UseCases.ets` — 角色提取 + 角色图生成 + 分镜参考图注入
11. `pages/ProjectDetailPage.ets` — UI 按钮

## 已知限制

- 角色图片是逐个串行生成，各角色之间不传参考图保持风格一致（后续可改进为方案 B：角色间互传参考图）
- `remapCharacterNamesToIds` 目前仅记录日志，未更新数据库（后续可集成到 reload 流程）
- 火山引擎/阿里万相适配器未包含在此次改动中（鸿蒙端仅使用 Agnes AI）
