# 鸿蒙端角色列表页面与单个角色图片生成

**日期**: 2026-08-06
**状态**: 已实现（含 2026-08-08 修复记录）

## Context

角色提取与分镜角色参考图功能（第一阶段，见 [[2026-08-06-harmony-character-storyboard-reference]]）已完成。现在需要在项目详情页持久展示角色数量、提供「查看角色」入口导航到专用角色列表页面。角色列表页面支持编辑角色的外观提示词（appearance），并为单个角色独立生成图片。

## 改动文件清单

| 文件 | 改动类型 |
|------|----------|
| `data/CharacterLocalDataSource.ets` | 修改 — 新增 `updateCharacterAppearance` |
| `data/DramaRepository.ets` | 修改 — 代理 `updateCharacterAppearance` |
| `usecase/UseCases.ets` | 修改 — 新增 `updateCharacterAppearance` 和 `generateSingleCharacterImage` |
| `resources/base/profile/main_pages.json` | 修改 — 注册 `pages/CharacterListPage` |
| `pages/ProjectDetailPage.ets` | 修改 — 角色数量展示 + 「查看角色」按钮（替换横向滚动卡片） |
| `pages/CharacterListPage.ets` | **新增** — 角色列表页面 |

## 详细实现步骤

### Step 1: CharacterLocalDataSource.ets — 新增 `updateCharacterAppearance`

参照已有 `updateCharacterImage` 的 SQL UPDATE 模式，新增方法更新 `appearance` 列和 `updated_at`：

```typescript
async updateCharacterAppearance(characterId: number, appearance: string): Promise<void> {
  const store = await DramaDatabase.getStore();
  const values: relationalStore.ValuesBucket = {
    'appearance': appearance,
    'updated_at': Date.now()
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', characterId);
  await store.update(values, predicates);
}
```

### Step 2: DramaRepository.ets — 代理方法

参照已有代理模式（如 `updateCharacterImage`），新增一行代理：

```typescript
async updateCharacterAppearance(characterId: number, appearance: string): Promise<void> {
  return this.characters.updateCharacterAppearance(characterId, appearance);
}
```

### Step 3: UseCases.ets — 新增两个静态方法

**3a. `updateCharacterAppearance`**（参照 `updateShotPrompt`）：

```typescript
static async updateCharacterAppearance(characterId: number, appearance: string): Promise<void> {
  return UseCases.repo.updateCharacterAppearance(characterId, appearance);
}
```

**3b. `generateSingleCharacterImage`**（从已有 `generateCharacterImages` 循环体提取，参数化为单角色）：

流程：
1. 获取角色 — 找不到返回错误
2. 跳过已完成且有本地文件的情况
3. 更新状态为 PROCESSING
4. 构建 prompt：`"{角色名}, {appearance}, 高质量, 正面"`
5. 调用 `AgnesImageRepository.generateImage()`
6. 下载到本地 `downloadCharImage()`
7. 更新状态为 COMPLETED 或 FAILED

### Step 4: main_pages.json — 注册新页面

在 `src` 数组末尾追加 `"pages/CharacterListPage"`。

### Step 5: ProjectDetailPage.ets — 角色数量 + 查看按钮

**替换**横向滚动卡片区域（原 576-622 行），改为：

- **角色数量行**：`Text("已提取 N 个角色")`，仅 `characters.length > 0` 时显示
- **「查看角色」按钮**：全宽 `Theme.surfaceAlt` 风格，参照「查看脚本」按钮，`enabled: hasCharacters`，点击跳转 `router.pushUrl({ url: 'pages/CharacterListPage', params: { projectId } })`

### Step 6: CharacterListPage.ets — 新页面（新增）

参照 `StoryboardViewerPage.ets` 的布局模式：

- **顶部栏**：返回按钮 + 项目标题 + 角色计数
- **列表**：`List` + `ForEach` 渲染角色卡片
- **卡片内容**：
  - 左侧缩略图/占位（64x64），右侧角色名（bold）和角色类型（secondary）
  - 右上角图片状态标识（PROCESSING 时显示「生成中…」）
  - 外貌描述文字（appearance），标题「外貌描述」
  - 操作按钮行：「编辑提示词」（surfaceAlt）+「生成图片」（primary）
- **编辑弹层**：参照 `StoryboardViewerPage` 的 overlay 模式，背景遮罩 + 居中对话框 + TextArea + 取消/保存
- **单角色生成**：调用 `UseCases.generateSingleCharacterImage`，用 `generatingCharId` 跟踪当前生成的角色，生成完后 `reloadCharacters()`

UI 配色沿用 `Theme` 类（bg=#121212, surface=#1E1E1E, primary=#E53935）。

## 数据流

```
详情页 → 提取角色 → 显示"已提取 N 个角色" → 点击「查看角色」
→ 角色列表页 → 编辑提示词（弹层修改 appearance）→ 保存
→ 点击「生成图片」→ 单个角色图片生成 → 缩略图更新
```

## 验证方式

1. 编译：`cd ZdramaHarmony && devecocli build`
2. 走读数据流：详情页点击「查看角色」→ 角色列表页 → 编辑提示词 → 保存 → 生成图片 → 缩略图更新

---

## 2026-08-08 修复记录

### 现象
详情页点击「生成角色图」时，若 4 个角色图均已生成完成（全部走 skip 分支），UI 仍弹出 `失败：角色图生成失败` toast。日志显示 `generateCharacterImages done: ok=4/4`，但函数实际返回 `{ ok: false, error: '角色图生成失败' }`。

### 根因
`UseCases.generateCharacterImages` / `generateStoryboardImages` / `generateStoryboardVideos` 三个批量接口的返回值判断条件只覆盖「新生成数 > 0」的场景：

```typescript
if (generated > 0) {
  return { ok: true, value: `${generated}`, error: '' };
}
return { ok: false, value: '', error: firstError.length > 0 ? firstError : '角色图生成失败' };
```

当所有资源都已存在（`completed === total`，但 `generated === 0`，且无 `firstError`）时，函数错误地返回 `ok=false`。日志里 `ok=4/4` 看的是 `completed`，UI toast 看的是 `result.ok`，二者口径不一致。

### 修复方案
三个批量接口统一在 `if (generated > 0)` 之前增加「全部完成 → ok=true」早返回：

```typescript
if (completed === total) {
  // 全部成功（含已存在跳过）即视为成功
  return { ok: true, value: `${generated}`, error: '' };
}
if (generated > 0) {
  return { ok: true, value: `${generated}`, error: '' };
}
return { ok: false, value: '', error: firstError.length > 0 ? firstError : '角色图生成失败' };
```

### 修复后语义

| 场景 | `completed` | `generated` | `firstError` | 返回 |
|---|---|---|---|---|
| 全部新生成成功 | total | > 0 | `''` | `ok=true` |
| 全部已存在跳过 | total | 0 | `''` | `ok=true` **(新)** |
| 部分失败 + 部分新生成 | < total | > 0 | 非空 | `ok=true` |
| 全部失败 | < total | 0 | 非空 | `ok=false` |
| 全部失败 + 无具体错误 | < total | 0 | `''` | `ok=false` |

### 改动清单

| 文件 | 改动 |
|---|---|
| `usecase/UseCases.ets` `generateStoryboardImages` | 新增 `if (completed === shots.length)` 早返回 (line 361-368) |
| `usecase/UseCases.ets` `generateStoryboardVideos` | 新增 `if (completed === shots.length)` 早返回 (line 466-473) |
| `usecase/UseCases.ets` `generateCharacterImages` | 新增 `if (completed === characters.length)` 早返回 (line 666-673) |
| `usecase/UseCases.ets` `generateSingleCharacterImage` | skip 分支补 `hilog.info` 日志 (line 690)，与批量版日志口径一致 |

### 验证
- 编译：`cd ZdramaHarmony && devecocli build` → BUILD SUCCESSFUL in 20 s
- 用户操作：详情页点击「生成角色图」→ 4 张图均为已存在 → 旧版本 toast「失败：角色图生成失败」；新版本 toast「角色图已生成」
