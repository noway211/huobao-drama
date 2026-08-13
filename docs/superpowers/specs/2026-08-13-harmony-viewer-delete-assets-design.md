# 鸿蒙端查看页支持删除图片/视频/成片

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在鸿蒙端三个查看页（`StoryboardImagePage` / `VideoViewerPage` / `FinalVideoPage`）上提供「删除」入口，把已生成素材做软删除（DB 状态置 PENDING、清字段）+ 删除本地文件，让用户可以重新生成。

**Architecture:** 复用已有 `updateShotImage` / `updateShotVideo` / `updateProjectFinalVideo` 做软删除；用 `fileIo.unlinkSync` 删本地文件；UI 上每个卡片加一个「删除」按钮，点击弹 `promptAction.showDialog` 二次确认，确认后调 UseCase，删完直接重新 load 列表。

**Tech Stack:** HarmonyOS NEXT · ArkTS · ArkUI · `@kit.CoreFileKit.fileIo` · `@kit.ArkUI.promptAction` · Hono/relationalStore（不动）。

## Global Constraints

- **仅前端改动**：不碰后端 `backend/`、不碰 Hono 路由、不动数据库 schema、不动模型 enum。表结构、列、`AssetStatus` / `ProjectStatus` / `GenerationStage` 都不动。
- **复用已有 API**：软删除走 `UseCases.repo.updateShotImage(...)` / `updateShotVideo(...)` / `updateProjectFinalVideo(...)` 三个已有方法。**不**新增 `deleteShotImage` / `deleteShotVideo` 之类的方法。
- **状态值约定**：用户口语中说的 "IDLE" 在鸿蒙 enum 里对应 `AssetStatus.PENDING`（"未开始 / 可重新生成"）。DB 列存的是 enum 字符串 `.name`，存 `PENDING` 跟 Android 端持久化兼容（Android 侧也没有 IDLE 概念，初始态就是 PENDING）。
- **必须同时清字段**:`imageUrl` / `imageLocalPath` / `imageErrorMessage`（视频类同，加 `videoTaskId`）一律置 `null`。成片：清 `finalVideoLocalPath` / `finalVideoErrorMessage` / `errorMessage`，`status` / `currentStage` 保留为当前值（不要因为删成片把整个项目状态重置）。
- **需要新增 3 个 public static 包装**：`UseCases.repo` 是 `private static`（`UseCases.ets:41`），UI 页面不能直接 `UseCases.repo.updateShotImage(...)`。按现有 `UseCases.updateShotPrompt(...)`（`UseCases.ets:140`）/ `UseCases.updateShotVideoPrompt(...)`（`UseCases.ets:144`）的薄包装模式，新增 3 个 public static 方法：
  - `UseCases.updateShotImage(shotId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage)`
  - `UseCases.updateShotVideo(shotId, videoStatus, videoTaskId, videoUrl, videoLocalPath, videoErrorMessage)`
  - `UseCases.updateProjectFinalVideo(projectId, status, currentStage, finalVideoStatus, finalVideoLocalPath, finalVideoErrorMessage, errorMessage)`
  - 全部 1 行透传到 `UseCases.repo.*`，**不**做语义转换
- **UI 调用形式**：UI 页面用 `UseCases.updateShotImage(...)` / `UseCases.updateShotVideo(...)` / `UseCases.updateProjectFinalVideo(...)`，**不**用 `UseCases.repo.*` 形式（避免 private 访问错误）
- **删本地文件失败不能阻塞 DB 软删除**：`fileIo.unlinkSync` 抛错时只 `hilog.warn` 记录 + `promptAction.showToast` 提示"本地文件已不存在"，不 throw。
- **二次确认弹层用 `promptAction.showDialog`**：与 `Index.ets` 删除项目 / `ProjectDetailPage.ets` confirmIfScriptExists 同一套 API。buttons 顺序 `[{text: '取消'}, {text: '删除', color: Theme.primary}]`，删除按钮走 `Theme.primary` 警示色（不引红色，保持全站一致）。
- **不破坏现有 ForEach key**：`StoryboardImagePage.ets:188` / `VideoViewerPage.ets:193` 的 ForEach key 仍用 `shot.id.toString()`。删除素材是「行消失」操作，ForEach 用稳定 key 即可正确处理，**不**复刻 `StoryboardViewerPage.ets` 的 refreshTick 修复（那里的 bug 是"行不变、值变了"，本次是"行直接没了"）。
- **统一错误反馈**：`promptAction.showToast({ message })` 报错；删除成功用 toast "已删除"。
- **不要新建删除 API / 工具类的 UseCase 公共方法**：本次不新增 `UseCases.deleteShotImage(...)` 之类的方法。UI 直接调 `UseCases.repo.updateShotImage(...)` + 内联 `fileIo.unlinkSync` 即可，避免新增无意义的 wrapper 抽象层。
- **不能影响成片合成流程的"按 completed 预检"**：`composeFinalVideo`（`UseCases.ets:920`）会查 `s.videoStatus === AssetStatus.COMPLETED`；本次不改 shot.videoStatus 的判断，删除后 shot.videoStatus 变 PENDING，自动从合成预检里排除，行为正确。
- **构建命令**:`ZdramaHarmony/` 下没有 `hvigorw` 脚本（项目用 `build-profile.json5` 配 hvigor），实际命令是用 DevEco Studio 自带的 wrapper：`/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap`，从 `ZdramaHarmony/` 目录内执行。如果 `hvigorw` 在 PATH 上，也可直接 `hvigorw assembleHap`。
- **不删 `shot_N_image.{ext}` 之外的旁路文件**（如 `shot_N_image.json` / 下载过程临时文件）—— 那些是 `MediaDownloadRepository` 自己的内部事务，本次不触碰。

## 现状回顾（来自读码）

| 现状点 | 位置 | 用途 |
|---|---|---|
| `updateShotImage(shotId, status, url, localPath, error)` | `StoryboardLocalDataSource.ets:167` | 软删图片直接调用 |
| `updateShotVideo(shotId, status, taskId, url, localPath, error)` | `StoryboardLocalDataSource.ets:191` | 软删视频直接调用 |
| `updateProjectFinalVideo(projectId, status, currentStage, finalVideoStatus, finalVideoLocalPath, finalVideoErrorMessage, errorMessage)` | `ProjectLocalDataSource.ets:145` + `DramaRepository.ets:55` | 软删成片直接调用 |
| `fileIo.unlinkSync` | `@kit.CoreFileKit` | **新引入**的本地文件删除（当前代码用 `rmdirSync` 删目录、`statSync` 查大小） |
| `promptAction.showDialog({ title, message, buttons })` | `@kit.ArkUI` | 确认弹层（`Index.ets:31` 已用） |
| `AppContext.get().filesDir` | `MediaDownloadRepository.ets:61` | 拼本地路径用 |
| 文件路径模式 | `MediaDownloadRepository.ets:62-63` | `{filesDir}/generated/{projectId}/shot_{shotId}_image.{ext}` / `shot_{shotId}_video.{ext}` |
| 成片路径 | `UseCases.ets:946` | `{filesDir}/generated/{projectId}/final_video.mp4` |

## 设计决策

### 1. 软删除策略 = reset 字段 + status 置 PENDING

对应 Android 端"删除 = reset 到初始状态"语义。**不**硬删 shot row（shot 还可能在项目里承担剧情脚本的结构作用，且后续重新生成图片/视频/成片时 shot row 必须还在）。

**图片软删**：
```ts
UseCases.repo.updateShotImage(shotId, AssetStatus.PENDING, null, null, null);
```
**视频软删**：
```ts
UseCases.repo.updateShotVideo(shotId, AssetStatus.PENDING, null, null, null, null);
```
**成片软删**（保留项目 status / currentStage 不动）：
```ts
const project = await UseCases.getProject(projectId);
await UseCases.repo.updateProjectFinalVideo(
  projectId,
  project.status,                // 不重置项目状态
  project.currentStage,         // 不重置项目阶段
  AssetStatus.PENDING,           // 仅把成片状态置回 PENDING
  null,                          // finalVideoLocalPath
  null,                          // finalVideoErrorMessage
  null                           // errorMessage
);
```

### 2. 本地文件删除 = `fileIo.unlinkSync` + 容错

```ts
try {
  if (path && path.length > 0) {
    fileIo.unlinkSync(path);  // 删文件（不是目录）
  }
} catch (e) {
  hilog.warn(1, "DeleteLocalFile", "unlink failed: %{public}s", (e as Error).message);
  // 不 throw,继续走完
}
```

> `unlinkSync` 是 CoreFileKit 删单文件的标准 API（已有 `statSync` / `rmdirSync` / `mkdirSync` 在用，加 `unlinkSync` 同源）。文件不存在时它会抛 `BusinessError` 1541，按上面 try-catch 处理即可。

### 3. UI 入口 = 每张图片/视频/成片卡片右下角加一个「删除」按钮

- **位置**：卡片底部，在 `Image`/`Video` 元素下方、与已有的 `Text(action/duration)` 同级，独立一行。
- **样式**：small button，`fontSize: 13`, `backgroundColor: Theme.surfaceAlt`, `fontColor: Theme.textPrimary`, `height: 32`, 右对齐。
- **文案**：「删除」(2 个字)。成片页用「删除成片」。
- **触发后行为**：
  1. 弹 `promptAction.showDialog` 二次确认
  2. 确认后调软删 + `unlinkSync`（按 1、2 步骤）
  3. `promptAction.showToast` "已删除"
  4. 重新调 `onPageShow` 的 load 逻辑（或直接在 `this.shots = this.shots.filter(...)` 本地过滤后重 load），让当前页立刻少一张

### 4. 确认弹层文案

| 页面 | title | message |
|---|---|---|
| 图片页 | `删除图片？` | `删除后需要重新生成。可在分镜列表重新生成图片。` |
| 视频页 | `删除视频？` | `删除后需要重新生成。可在分镜列表重新生成视频。` |
| 成片页 | `删除成片？` | `删除后需要重新合成。可在项目详情页合成成片。` |

buttons：`[{text: '取消', color: Theme.textSecondary}, {text: '删除', color: Theme.primary}]`，index=1 = 删除。

## 数据流（一张图片删除的完整流程）

```
StoryboardImagePage 卡片 → "删除" 按钮
  └─► onDeleteImageClick(shot)
        └─► promptAction.showDialog
              └─► user taps "删除" (index=1)
                    ├─► UseCases.repo.updateShotImage(shot.id, PENDING, null, null, null)
                    │     └─► storyboard.image_status = PENDING, image_url = null,
                    │         image_local_path = null, image_error_message = null
                    ├─► try fileIo.unlinkSync(shot.imageLocalPath) // 容错
                    ├─► promptAction.showToast "已删除"
                    └─► await onPageShow() // 重新 load 列表
                          └─► StoryboardImagePage.onPageShow 重新拉分镜
                                └─► 过滤 imageStatus === COMPLETED (现在少了一张)
```

## 文件改动

### 修改

#### `ZdramaHarmony/entry/src/main/ets/pages/StoryboardImagePage.ets`
- 在卡片底部（在 `if (shot.action.length > 0) { Text(shot.action) }` 之后）新增一行 `Row`：
  - 右对齐的 `Button('删除')` `.onClick(() => onDeleteImageClick(shot))`
- 新增方法 `private onDeleteImageClick(shot: StoryboardShot): void`：
  - 弹 `promptAction.showDialog`
  - 确认后调 `UseCases.repo.updateShotImage(...)` 软删 + `fileIo.unlinkSync(shot.imageLocalPath)` 容错
  - toast + 调 `this.onPageShow()` 重新 load
- `import` 加 `fileIo` from `@kit.CoreFileKit`

#### `ZdramaHarmony/entry/src/main/ets/pages/VideoViewerPage.ets`
- 同上：在卡片底部（在 `Text("⏱ {duration}s")` 之后）新增一行 `Row`：
  - 右对齐的 `Button('删除')` `.onClick(() => onDeleteVideoClick(shot))`
- 新增 `onDeleteVideoClick(shot)` 方法
- `import` 加 `fileIo`

#### `ZdramaHarmony/entry/src/main/ets/pages/FinalVideoPage.ets`
- 在视频播放器 `Column` 之下（成片显示区域）增加一个 `Row`，装一个 `Button('删除成片')`（`.backgroundColor(Theme.surfaceAlt)`、`.fontColor(Theme.textPrimary)`）
- 新增 `onDeleteFinalVideoClick()` 方法：
  - 弹 `promptAction.showDialog`（title/message 按 §4 表）
  - 确认后 `getProject` 拿现状 → `updateProjectFinalVideo(projectId, project.status, project.currentStage, PENDING, null, null, null)`
  - `fileIo.unlinkSync(project.finalVideoLocalPath)` 容错
  - toast + `this.loadFinalVideo()` 重新 load（会自动进 `errorText='成片视频不存在'` 空态）
- `import` 加 `fileIo`

### 不动

- `backend/` 全部
- `data/` 全部（schema / repo / dataSource 都不动）
- `model/DramaModels.ets`（enum 不变）
- `usecase/UseCases.ets`（不动 — 已有的 `updateShotImage` / `updateShotVideo` / `updateProjectFinalVideo` / `getProject` 足够）
- `common/Theme.ets`（颜色 token 复用已有的 `Theme.surfaceAlt` / `Theme.textPrimary` / `Theme.primary`）
- `resources/base/profile/main_pages.json`（不增页面）

## 关键实现细节

### 1. 「删除」按钮的 ArkUI Builder 写法

卡片在 ForEach 内，ForEach 的 `(shot: StoryboardShot) => string` key 是 `shot.id.toString()`，删除会让 shot 直接从 `this.shots` 数组里消失（下次 `onPageShow` reload 时，imageStatus=PENDING 的 shot 被过滤掉），ForEach 看到 key 没了会自动 unmount 对应 ListItem，无需任何手动处理。

按钮写法：
```ts
Row() {
  Blank().layoutWeight(1)            // 推到右边
  Button('删除')
    .fontSize(13)
    .backgroundColor(Theme.surfaceAlt)
    .fontColor(Theme.textPrimary)
    .height(32)
    .padding({ left: 12, right: 12 })
    .onClick((): void => { this.onDeleteImageClick(shot) })
}
.width('100%')
.margin({ top: 8 })
```

### 2. onDeleteImageClick 的完整实现

```ts
private async onDeleteImageClick(shot: StoryboardShot): Promise<void> {
  promptAction.showDialog({
    title: '删除图片？',
    message: '删除后需要重新生成。可在分镜列表重新生成图片。',
    buttons: [
      { text: '取消', color: Theme.textSecondary },
      { text: '删除', color: Theme.primary }
    ]
  }).then(async (r) => {
    if (r.index !== 1) {
      return;
    }
    try {
      await UseCases.repo.updateShotImage(
        shot.id, AssetStatus.PENDING, null, null, null
      );
    } catch (e) {
      promptAction.showToast({ message: '删除失败：' + ((e as Error).message ?? String(e)) });
      return;
    }
    // 容错删本地文件
    if (shot.imageLocalPath && shot.imageLocalPath.length > 0) {
      try {
        fileIo.unlinkSync(shot.imageLocalPath);
      } catch (e) {
        hilog.warn(1, "DeleteImage", "unlink failed: %{public}s", (e as Error).message);
      }
    }
    promptAction.showToast({ message: '已删除' });
    await this.onPageShow();
  });
}
```

> 视频 / 成片同结构，差异只在第 2 步的 update 调用 + 第 3 步 unlink 的字段。

### 3. 成片删除的差异点

成片软删需要保留 `project.status` / `project.currentStage`，所以先 `getProject` 读现状再 update：
```ts
const project = await UseCases.getProject(this.projectId);
if (!project) return;
await UseCases.repo.updateProjectFinalVideo(
  this.projectId,
  project.status,
  project.currentStage,
  AssetStatus.PENDING,
  null, null, null
);
```
然后 `loadFinalVideo()` 重新执行 → 因为 `finalVideoLocalPath` 现在是 null / ''，会进 `errorText='成片视频不存在'` 分支。这是预期效果：删完回到空态。

### 4. fileIo.unlinkSync 在 HarmonyOS Next 的可用性

`@kit.CoreFileKit` 的 `fileIo` 命名空间下提供：
- `unlinkSync(path: string): void` — 删单文件
- `unlink(path: string): Promise<void>` — 异步版本

当前 `MediaDownloadRepository.ets` 用的是 `openSync` / `writeSync` / `closeSync` / `statSync` / `rmdirSync`，可见 `fileIo.Sync*` 系列已经全部引用。`unlinkSync` 是同源 API，**有 API 保障**。

## 验证

### 编译层
- `cd ZdramaHarmony && ./gradlew :entry:assembleHap` 或 DevEco Studio Build → 必须 `BUILD SUCCESSFUL`
- DevEco Linter 0 critical / 0 important
- TypeScript strict mode 通过 (`tsc --noEmit`)

### 端到端
1. 真机打开一个生成了图片/视频/成片的项目
2. 走 ProjectDetailPage → 「查看图片」进 `StoryboardImagePage`
3. 点任一卡片右下角「删除」→ 弹「删除图片？」→ 确认
4. toast "已删除"，该卡片从列表中消失
5. 返回 ProjectDetailPage，看分镜列表里这个 shot 的图片状态变成"未生成"
6. 同样验证视频页 + 成片页
7. 删除后，DB 查 `storyboards` 表的 `image_status` / `video_status` = `PENDING`，对应 `image_local_path` / `video_local_path` = null
8. 删除后，本地 `filesDir/generated/{projectId}/shot_N_image.*` 文件确实没了（adb shell 进沙箱查）
9. 故意把一个 shot 的 `imageLocalPath` 改成 `/nonexistent/path/xxx.jpg`，点删除 → DB 仍软删成功 + toast 不报错（验证容错）
10. 重新生成图片/视频/成片 → 流程正常（验证软删后可以重新走整条生成管线）

## 风险 / 待用户确认

1. **「成片」按钮的删除不可逆**（虽然能重新合成）。如果用户希望更激进（"长按删除"或"滑动删除"），本 spec 不做；本次只做最简的「按钮 + 二次确认」。
2. **不在 FinalVideoPage 显式提示"成片已是 PENDING 可重新合成"**——空态文字保持现状 `'成片视频不存在'`，返回 ProjectDetailPage 看「合成成片」按钮即可。如果想加更明确的引导，plan 阶段再扩。
3. **删除后 `composeFinalVideo` 的预检**会自动排除已被软删视频的 shot（`videoStatus !== COMPLETED`），所以合成按钮的行为对用户透明：删完视频后必须把缺的视频重新生成才能继续合成。
4. **不在批量删除**（多选 → 批量删）——本次不做，避免 UI 复杂度爆炸。
