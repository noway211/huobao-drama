# 鸿蒙查看页支持删除图片/视频/成片 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `StoryboardImagePage` / `VideoViewerPage` / `FinalVideoPage` 三个查看页上为每个素材卡片新增「删除」按钮,二次确认后做软删除(状态置 PENDING + 清字段)并删本地文件,允许用户重新生成。

**Architecture:** 复用已有 `UseCases.repo.updateShotImage` / `updateShotVideo` / `updateProjectFinalVideo` 三个 DB update 方法做软删,新增 `fileIo.unlinkSync` 删除本地文件;UI 上每张卡片右下角加一个 `Button('删除')`,点击弹 `promptAction.showDialog` 二次确认,确认后调软删 + 容错 unlink + toast + 重新 load 列表。

**Tech Stack:** HarmonyOS NEXT / ArkTS / ArkUI / `@kit.CoreFileKit.fileIo` / `@kit.ArkUI.promptAction`

## Global Constraints

- 鸿蒙数据库 schema 不变,enum 不变,不动 `backend/` / `data/` / `model/DramaModels.ets` / `common/Theme.ets`
- **`UseCases.repo` 是 `private static`,UI 不能直接调**:按现有 `UseCases.updateShotPrompt(...)`（`UseCases.ets:140`）/ `UseCases.updateShotVideoPrompt(...)`（`UseCases.ets:144`）的薄包装模式,新增 3 个 public static 方法 `UseCases.updateShotImage(...)` / `UseCases.updateShotVideo(...)` / `UseCases.updateProjectFinalVideo(...)`,UI 调用 `UseCases.updateShotImage(...)` 形式,**不**用 `UseCases.repo.*` 形式
- 软删除走新增的 3 个 public wrapper,**不**新增 `deleteImage` / `deleteVideo` 之类的语义 API
- 删除后 status = `AssetStatus.PENDING`(语义:"未开始,可重新生成"),不是 IDLE(Harmony enum 没有 IDLE,PENDING 是最近似值,与 Android 端持久化字符串保持一致)
- 删除必须清字段:图片类清 `imageUrl` / `imageLocalPath` / `imageErrorMessage` 三个为 null;视频类多清 `videoTaskId`;成片清 `finalVideoLocalPath` / `finalVideoErrorMessage` / `errorMessage` 三个为 null,**保留** `project.status` / `project.currentStage`(成片是子资产,删完不影响项目整体状态)
- 本地文件删除用 `fileIo.unlinkSync(path)`,CoreFileKit 同步 API(同源系列已有 `openSync` / `writeSync` / `statSync` / `rmdirSync` 在用);失败必须容错(hilog.warn + 不 throw)
- 二次确认弹层用 `promptAction.showDialog`,与 `Index.ets:31` 删除项目 / `ProjectDetailPage.ets:110` 二次确认同套 API;buttons 顺序 `[{text: '取消', color: Theme.textSecondary}, {text: '删除', color: Theme.primary}]`
- 「删除」按钮放卡片右下角:`Row { Blank().layoutWeight(1); Button('删除')... }` 推到右边
- 主题色只用已有 `Theme.surface` / `Theme.surfaceAlt` / `Theme.primary` / `Theme.textPrimary` / `Theme.textSecondary`,不硬编码颜色
- 反馈用 `promptAction.showToast`;删除成功 toast "已删除",失败 toast "删除失败: {msg}"
- 不复刻 `StoryboardViewerPage` 的 refreshTick ForEach 修复 — 删素材是「行消失」操作,ForEach 用稳定 key 即可正确处理
- 写代码风格:与同文件现有方法保持一致(参考 `Index.ets:31` 的 `confirmDelete` / `ProjectDetailPage.ets:105` 的 `confirmIfScriptExists`)
- 不加批量删除、不加长按菜单、不动 `composeFinalVideo` 预检逻辑(预检 `videoStatus === AssetStatus.COMPLETED` 自动从合成预检里排除已被软删视频的 shot,行为正确)
- import 必须命名导入;新增 import `fileIo` from `@kit.CoreFileKit`(如果文件还没 import 的话)
- struct 普通方法(返回 void)构造 UI 节点,不用 `@Builder` 函数(避免 @Builder 不能引用 `this` 的限制)

---

### Task 0: UseCases 新增 3 个 public static wrapper(数据层透传)

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`(在 `updateShotVideoPrompt` 方法 line 144-147 之后插入 3 个新方法)

**Interfaces:**
- Consumes: 现有 `UseCases.repo` (private static) 上的 `updateShotImage` / `updateShotVideo` / `updateProjectFinalVideo`
- Produces:
  - `UseCases.updateShotImage(shotId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage): Promise<void>`
  - `UseCases.updateShotVideo(shotId, videoStatus, videoTaskId, videoUrl, videoLocalPath, videoErrorMessage): Promise<void>`
  - `UseCases.updateProjectFinalVideo(projectId, status, currentStage, finalVideoStatus, finalVideoLocalPath, finalVideoErrorMessage, errorMessage): Promise<void>`

> 这是必要的中间层 — `UseCases.repo` 是 `private static`(`UseCases.ets:41`),UI 页面无法直接调。完全按现有 `updateShotPrompt` / `updateShotVideoPrompt`(`UseCases.ets:140-147`)的 1 行透传模式做。

- [ ] **Step 1: 在 `UseCases.ets` 插入 3 个新 public static 方法**

定位 `updateShotVideoPrompt` 方法(line 144-147),在它之后插入:

```ts
/** 更新单个分镜的图片资产（用于软删除：传 PENDING + nulls）。 */
static async updateShotImage(
  shotId: number,
  imageStatus: AssetStatus,
  imageUrl: string | null,
  imageLocalPath: string | null,
  imageErrorMessage: string | null
): Promise<void> {
  return UseCases.repo.updateShotImage(shotId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage);
}

/** 更新单个分镜的视频资产（用于软删除：传 PENDING + nulls）。 */
static async updateShotVideo(
  shotId: number,
  videoStatus: AssetStatus,
  videoTaskId: string | null,
  videoUrl: string | null,
  videoLocalPath: string | null,
  videoErrorMessage: string | null
): Promise<void> {
  return UseCases.repo.updateShotVideo(
    shotId, videoStatus, videoTaskId, videoUrl, videoLocalPath, videoErrorMessage);
}

/** 更新项目的成片资产（用于软删除：传 PENDING + nulls,保留项目 status / currentStage）。 */
static async updateProjectFinalVideo(
  projectId: number,
  status: ProjectStatus,
  currentStage: GenerationStage,
  finalVideoStatus: AssetStatus,
  finalVideoLocalPath: string | null,
  finalVideoErrorMessage: string | null,
  errorMessage: string | null
): Promise<boolean> {
  return UseCases.repo.updateProjectFinalVideo(
    projectId, status, currentStage, finalVideoStatus,
    finalVideoLocalPath, finalVideoErrorMessage, errorMessage);
}
```

> import 不用改 — `AssetStatus` / `ProjectStatus` / `GenerationStage` 已经在文件顶部 import 了(`UseCases.ets:1-15` 区域)。`StoryboardShot` / `DramaProject` 也都已 import。
> `updateProjectFinalVideo` 返回 `Promise<boolean>`(与 `repo.updateProjectFinalVideo` 透传一致,`DramaRepository.ets:67` 那一层把 `rows > 0` 转成 boolean),前两个返回 `Promise<void>`(与 `repo.updateShotImage` / `repo.updateShotVideo` 一致)。

- [ ] **Step 2: 编译验证**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
```

期望:`> hvigorw BUILD SUCCESSFUL`。只改了 UseCases.ets,Task 1-3 还没做,只验证新增 3 个方法编译通过。

> 备注:项目根目录的 `ZdramaHarmony/` 下没有 `hvigorw` 脚本(项目用 `build-profile.json5` + `hvigorfile.ts` 配 hvigor),构建器来自 DevEco Studio 的安装目录。如果 `hvigorw` 已经在 PATH 上,也可直接 `hvigorw assembleHap`。

- [ ] **Step 3: 提交**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "feat(harmony): UseCases 暴露 updateShotImage/updateShotVideo/updateProjectFinalVideo 三个 public 包装"
```

提交信息体写明:
- 3 个 1 行透传,完全照搬 `updateShotPrompt` / `updateShotVideoPrompt` 的现有模式
- 不动 data layer,不改任何业务逻辑
- UI 删除功能需要这 3 个方法才能调(后续 Task 1-3 消费)

---

### Task 1: `StoryboardImagePage` 删除图片功能

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/pages/StoryboardImagePage.ets`(整文件,主要集中在 3 处:import / 新方法 / 卡片底部)

**Interfaces:**
- Consumes:
  - 现有 `StoryboardShot` / `AssetStatus`(已在 import)
  - **Task 0 新增** `UseCases.updateShotImage(shotId, status, url, localPath, errorMessage)`(public 包装)
  - 现有 `UseCases.getStoryboards(projectId)`(用于重新 load 列表)
  - 现有 `Theme.surfaceAlt` / `Theme.primary` / `Theme.textSecondary`(已存在)
  - `fileIo.unlinkSync(path)` from `@kit.CoreFileKit`
  - `promptAction.showDialog` / `promptAction.showToast`(已 import)
- Produces:
  - `onDeleteImageClick(shot: StoryboardShot): void` 私有方法
  - 每张图片卡片右下角「删除」按钮

> 关键:UI 调 `UseCases.updateShotImage(...)`(**不**用 `UseCases.repo.updateShotImage(...)`,后者是 private 不可见)。

- [ ] **Step 1: 修改文件顶部 import**

修改 line 1-5,从:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';
```

改为:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';
```

> 注意 import 顺序:`@kit.*` 在前,相对路径在后。已有 `hilog` 在 line 5 也要保留。

- [ ] **Step 2: 在 `openFullscreen` 方法之后新增 `onDeleteImageClick` 方法**

定位 `openFullscreen` 方法(line 77-84,在 `imgSrc` 之前),在它之后插入新方法:

```ts
// 二次确认 → 软删除(状态置 PENDING、清字段) + 容错删本地文件 + 重新 load
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
      await UseCases.updateShotImage(
        shot.id, AssetStatus.PENDING, null, null, null
      );
    } catch (e) {
      promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
      return;
    }
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

- [ ] **Step 3: 在卡片底部加「删除」按钮**

定位 `if (shot.action.length > 0)` 块(line 173-180,展示 `shot.action` 文案),在它之后、整个 `Column` 结束之前(line 181 那个 `.padding(12).width('100%')` 之前),新增一行:

```ts
// 删除按钮(右下角)
Row() {
  Blank().layoutWeight(1)
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

> 这里的 `shot` 是 ForEach 回调里的 `shot: StoryboardShot` 参数,直接闭包捕获即可。

- [ ] **Step 4: 编译验证**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
```

期望:`> hvigorw BUILD SUCCESSFUL`。Task 0 已经提交,Task 2/3 还没做,验证 Task 0+1 同时编译通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/pages/StoryboardImagePage.ets
git commit -m "feat(harmony): StoryboardImagePage 删除图片功能"
```

提交信息体写明:
- 卡片右下角新增「删除」按钮,弹 `promptAction.showDialog` 二次确认
- 软删: `UseCases.repo.updateShotImage(shotId, PENDING, null, null, null)` 清字段 + imageStatus
- 本地文件:`fileIo.unlinkSync(shot.imageLocalPath)`,失败仅 hilog.warn 不 throw
- 删完调 `this.onPageShow()` 重新 load,被软删的 shot 因 imageStatus=PENDING 自动从列表过滤掉
- 不新增 useCase / data layer API,完全复用已有 update 方法
- 不复刻 StoryboardViewerPage 的 refreshTick 修复 — 删素材是「行消失」,ForEach 稳定 key 即可正确处理

---

### Task 2: `VideoViewerPage` 删除视频功能

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/pages/VideoViewerPage.ets`(整文件,主要集中在 3 处:import / 新方法 / 卡片底部)

**Interfaces:**
- Consumes:
  - 现有 `StoryboardShot` / `AssetStatus`(已在 import)
  - **Task 0 新增** `UseCases.updateShotVideo(shotId, status, taskId, url, localPath, errorMessage)`(public 包装,6 参签名)
  - 现有 `Theme.*`(已存在)
  - `fileIo.unlinkSync(path)` from `@kit.CoreFileKit`
  - `promptAction.showDialog` / `promptAction.showToast`(已 import)
- Produces:
  - `onDeleteVideoClick(shot: StoryboardShot): void` 私有方法
  - 每段视频卡片右下角「删除」按钮

> 关键:UI 调 `UseCases.updateShotVideo(...)`(**不**用 `UseCases.repo.updateShotVideo(...)`,后者是 private 不可见)。

- [ ] **Step 1: 修改文件顶部 import**

修改 line 1-3,从:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';
```

改为:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';
```

> 注意:此文件之前没 import `hilog`,这里新增。

- [ ] **Step 2: 在 `shotMeta` 方法之后新增 `onDeleteVideoClick` 方法**

定位 `shotMeta` 方法(line 73-86,在 `videoSrc` 之后),在它之后插入新方法:

```ts
// 二次确认 → 软删除(状态置 PENDING、清字段,含 videoTaskId) + 容错删本地文件 + 重新 load
private async onDeleteVideoClick(shot: StoryboardShot): Promise<void> {
  promptAction.showDialog({
    title: '删除视频？',
    message: '删除后需要重新生成。可在分镜列表重新生成视频。',
    buttons: [
      { text: '取消', color: Theme.textSecondary },
      { text: '删除', color: Theme.primary }
    ]
  }).then(async (r) => {
    if (r.index !== 1) {
      return;
    }
    try {
      await UseCases.updateShotVideo(
        shot.id, AssetStatus.PENDING, null, null, null, null
      );
    } catch (e) {
      promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
      return;
    }
    if (shot.videoLocalPath && shot.videoLocalPath.length > 0) {
      try {
        fileIo.unlinkSync(shot.videoLocalPath);
      } catch (e) {
        hilog.warn(1, "DeleteVideo", "unlink failed: %{public}s", (e as Error).message);
      }
    }
    promptAction.showToast({ message: '已删除' });
    await this.onPageShow();
  });
}
```

> updateShotVideo 签名 6 参:`(shotId, videoStatus, videoTaskId, videoUrl, videoLocalPath, videoErrorMessage)`。删除时全 null + PENDING。

- [ ] **Step 3: 在卡片底部加「删除」按钮**

定位 `Text("⏱ ${shot.durationSeconds}s")` 块(line 181-185,在视频描述之后),在它之后、整个 `Column` 结束之前(line 186 那个 `.padding(12).width('100%')` 之前),新增一行:

```ts
// 删除按钮(右下角)
Row() {
  Blank().layoutWeight(1)
  Button('删除')
    .fontSize(13)
    .backgroundColor(Theme.surfaceAlt)
    .fontColor(Theme.textPrimary)
    .height(32)
    .padding({ left: 12, right: 12 })
    .onClick((): void => { this.onDeleteVideoClick(shot) })
}
.width('100%')
.margin({ top: 8 })
```

- [ ] **Step 4: 编译验证**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
```

期望:`> hvigorw BUILD SUCCESSFUL`。Task 0+1+2 同时编译通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/pages/VideoViewerPage.ets
git commit -m "feat(harmony): VideoViewerPage 删除视频功能"
```

提交信息体写明:
- 同 Task 1 的图片删除,差异:确认弹层文案"删除视频？",`updateShotVideo` 6 参全 null,删除对象是 `shot.videoLocalPath`
- 不复刻 refreshTick 修复,行消失场景稳定 key 即可

---

### Task 3: `FinalVideoPage` 删除成片功能

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/pages/FinalVideoPage.ets`(整文件,主要集中在 3 处:import / 新方法 / 播放器下方)

**Interfaces:**
- Consumes:
  - **Task 0 新增** `UseCases.updateProjectFinalVideo(projectId, status, currentStage, finalVideoStatus, finalVideoLocalPath, finalVideoErrorMessage, errorMessage)`(public 包装,7 参)
  - 现有 `UseCases.getProject(projectId)`(用于读取 project.status / project.currentStage 保留现状)
  - 现有 `Theme.*`(已存在)
  - `fileIo.unlinkSync(path)` from `@kit.CoreFileKit`
  - `promptAction.showDialog` / `promptAction.showToast`(已 import)
- Produces:
  - `onDeleteFinalVideoClick(): void` 私有方法
  - 播放器下方「删除成片」按钮

> 关键:UI 调 `UseCases.updateProjectFinalVideo(...)`(**不**用 `UseCases.repo.updateProjectFinalVideo(...)`,后者是 private 不可见)。

- [ ] **Step 1: 修改文件顶部 import**

修改 line 1-3,从:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { Theme } from '../common/Theme';
```

改为:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { UseCases } from '../usecase/UseCases';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';
```

- [ ] **Step 2: 在 `loadFinalVideo` 方法之后新增 `onDeleteFinalVideoClick` 方法**

定位 `loadFinalVideo` 方法(line 36-56,在 `aboutToAppear` 之后),在它之后插入新方法:

```ts
// 二次确认 → 软删成片(保留项目 status / currentStage,仅清成片子资产) + 容错删本地文件 + 重新 load
private async onDeleteFinalVideoClick(): Promise<void> {
  promptAction.showDialog({
    title: '删除成片？',
    message: '删除后需要重新合成。可在项目详情页合成成片。',
    buttons: [
      { text: '取消', color: Theme.textSecondary },
      { text: '删除', color: Theme.primary }
    ]
  }).then(async (r) => {
    if (r.index !== 1) {
      return;
    }
    let project;
    try {
      project = await UseCases.getProject(this.projectId);
    } catch (e) {
      promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
      return;
    }
    if (!project) {
      promptAction.showToast({ message: '项目不存在' });
      return;
    }
    try {
      // 保留项目 status / currentStage,仅把 finalVideoStatus 置 PENDING,清 finalVideoLocalPath / finalVideoErrorMessage / errorMessage
      await UseCases.updateProjectFinalVideo(
        this.projectId,
        project.status,
        project.currentStage,
        AssetStatus.PENDING,
        null, null, null
      );
    } catch (e) {
      promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
      return;
    }
    if (project.finalVideoLocalPath && project.finalVideoLocalPath.length > 0) {
      try {
        fileIo.unlinkSync(project.finalVideoLocalPath);
      } catch (e) {
        hilog.warn(1, "DeleteFinalVideo", "unlink failed: %{public}s", (e as Error).message);
      }
    }
    promptAction.showToast({ message: '已删除' });
    await this.loadFinalVideo();
  });
}
```

> `AssetStatus` 需要 import。如果项目里没有 import `AssetStatus`,需要追加 `import { AssetStatus } from '../model/DramaModels';`。

- [ ] **Step 3: 在播放器下方加「删除成片」按钮**

定位视频播放器 `Column` 块(line 122-150,展示 `Video({ src: this.videoSrc })` 等),在它内部、`Text('点击视频进入全屏播放')` 之后、整个 Column 结束前,新增:

```ts
// 删除成片按钮(右下角)
Row() {
  Blank().layoutWeight(1)
  Button('删除成片')
    .fontSize(13)
    .backgroundColor(Theme.surfaceAlt)
    .fontColor(Theme.textPrimary)
    .height(32)
    .padding({ left: 12, right: 12 })
    .onClick((): void => { this.onDeleteFinalVideoClick() })
}
.width('100%')
.margin({ top: 12 })
```

- [ ] **Step 4: 编译验证**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
```

期望:`> hvigorw BUILD SUCCESSFUL`。Task 0+1+2+3 同时编译通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/pages/FinalVideoPage.ets
git commit -m "feat(harmony): FinalVideoPage 删除成片功能"
```

提交信息体写明:
- 播放器下方新增「删除成片」按钮,弹 `promptAction.showDialog` 二次确认
- 软删:先 `UseCases.getProject` 读现状,再 `updateProjectFinalVideo(projectId, project.status, project.currentStage, PENDING, null, null, null)` — 保留项目 status / currentStage,仅清成片子资产
- 本地文件:`fileIo.unlinkSync(project.finalVideoLocalPath)`,失败仅 hilog.warn 不 throw
- 删完调 `this.loadFinalVideo()` 重新 load,会进 `errorText='成片视频不存在'` 空态
- 不动 `composeFinalVideo` 预检,软删视频的 shot 自动从合成预检里排除,删除语义自洽

---

## 验证

### 编译
```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
```
期望:`> hvigorw BUILD SUCCESSFUL`。

### 端到端(真机)
1. ProjectDetailPage → 「查看图片」进 `StoryboardImagePage`
2. 点任一卡片右下角「删除」→ 弹「删除图片？」→ 确认
3. toast "已删除",该卡片从列表消失
4. 同样验证 VideoViewerPage / FinalVideoPage
5. 删后 DB 查 `storyboards.image_status` / `video_status` = `PENDING`,对应 `*_local_path` = null
6. 删后本地 `filesDir/generated/{projectId}/shot_N_image.*` / `shot_N_video.*` / `final_video.mp4` 文件确实没了
7. 故意把一个 shot 的 `imageLocalPath` 改成不存在的路径,点删除 → DB 仍软删成功 + toast 不报错
8. 重新生成图片/视频/成片 → 流程正常,验证软删后可重新走完整生成管线
