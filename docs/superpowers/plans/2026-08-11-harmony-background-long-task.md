# 鸿蒙端长时后台任务实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `EntryAbility.onBackground` 申请 `DATA_TRANSFER` 长时任务，让切到后台时图片/视频生成与轮询不被系统打断；回到前台时释放长时任务。

**Architecture:** 新增 `common/BackgroundTaskCoordinator.ets` 封装 `startBackgroundRunning` + 持续通知；`UseCases` 用一个 `Set<number>` 跟踪正在生成的项目 ID，`onBackground` 看到非空时申请长时任务，`onForeground` 直接释放；`generateStoryboardImages` / `generateStoryboardVideos` 在入口用 try/finally 维护 Set。

**Tech Stack:** HarmonyOS API 9+，ETS 静态类型，背景任务（`@kit.BackgroundTasksKit`），WantAgent（`@kit.AbilityKit`），通知（`@kit.NotificationKit`），Hilog（`@kit.PerformanceAnalysisKit`）。

**Spec:** [2026-08-11-harmony-background-long-task-design.md](../specs/2026-08-11-harmony-background-long-task-design.md)

## 改动文件清单

| 文件 | 改动类型 |
|------|----------|
| `ZdramaHarmony/entry/src/main/module.json5` | 修改 — 新增 `KEEP_BACKGROUND_RUNNING` 权限 + `backgroundModes: dataTransfer` |
| `ZdramaHarmony/entry/src/main/ets/common/BackgroundTaskCoordinator.ets` | **新增** — 长时任务申请/释放 + 持续通知 |
| `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets` | 修改 — `activeGeneratingProjects` Set + `hasActiveGenerating` + `markGenerating`/`unmarkGenerating` + 两个 generate 入口 try/finally |
| `ZdramaHarmony/entry/src/main/ets/entryability/EntryAbility.ets` | 修改 — `onBackground`/`onForeground` 接入 coordinator |

## Global Constraints

- HarmonyOS API 9+；通知沿用默认 channel，不注册 slot
- 长时任务单次 `DATA_TRANSFER`；不主动 `updateBackgroundRunning`（用户接受单次申请 + 冷启动兜底）
- 业务逻辑零改动；只动结构与新文件
- `activeGeneratingProjects` 用 `Set<number>` 简单去重，**不持久化**（冷启动有 `resetOrphanProcessingProjects` 兜底）
- 持续通知文案固定为「正在生成分镜」+「点击返回应用查看进度」

---

## Task 1: 修改 `module.json5` — 声明后台运行权限与模式

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/module.json5`

**Interfaces:**
- Consumes: 现有 `requestPermissions` 数组与 `abilities[0]` EntryAbility
- Produces: 鸿蒙系统识别到 EntryAbility 支持 `dataTransfer` 后台模式并允许 `KEEP_BACKGROUND_RUNNING` 权限申请

- [ ] **Step 1: 添加 KEEP_BACKGROUND_RUNNING 权限**

在 `ZdramaHarmony/entry/src/main/module.json5` 中找到 `"requestPermissions"` 数组（当前 line 36-43），在 `GET_NETWORK_INFO` 后追加一条：

```json5
{
  "name": "ohos.permission.KEEP_BACKGROUND_RUNNING"
}
```

最终结果应类似：

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET"
  },
  {
    "name": "ohos.permission.GET_NETWORK_INFO"
  },
  {
    "name": "ohos.permission.KEEP_BACKGROUND_RUNNING"
  }
],
```

- [ ] **Step 2: 给 EntryAbility 添加 backgroundModes**

在同一文件 `abilities[0]` 对象中（当前 line 12-34，EntryAbility 声明），在 `"exported": true,` 之后、`"skills": [...]` 之前，插入：

```json5
      "backgroundModes": [
        "dataTransfer"
      ],
```

注意：JSON5 允许数组后有尾逗号；与现有字段风格保持一致，**数组内末尾不加逗号**。

- [ ] **Step 3: 验证 JSON5 语法**

DevEco Studio 会自动校验；用任意编辑器打开文件，确认两处修改都生效、无语法错。如果有 `node` 可用可做粗校验：

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
node -e "JSON.parse(require('fs').readFileSync('entry/src/main/module.json5','utf8').replace(/\/\/.*/g,'').replace(/\/\*[\s\S]*?\*\//g,''))" 2>&1 || true
```

注：此为粗校验 JSON5，DevEco 仍是最终裁判。

- [ ] **Step 4: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/module.json5
git commit -m "feat(harmony): 声明 KEEP_BACKGROUND_RUNNING 权限与 dataTransfer 后台模式"
```

---

## Task 2: 新增 `BackgroundTaskCoordinator.ets`

**Files:**
- Create: `ZdramaHarmony/entry/src/main/ets/common/BackgroundTaskCoordinator.ets`

**Interfaces:**
- Consumes: `common.UIAbilityContext`（项目里 `import { common } from '@kit.AbilityKit'` 已使用，见 [AppContext.ets](../../ZdramaHarmony/entry/src/main/ets/common/AppContext.ets)）
- Produces:
  - `static isActive(): boolean`
  - `static async acquire(context: common.UIAbilityContext): Promise<void>`
  - `static async release(context: common.UIAbilityContext): Promise<void>`

- [ ] **Step 1: 新建文件，写入完整实现**

创建文件 `ZdramaHarmony/entry/src/main/ets/common/BackgroundTaskCoordinator.ets`，内容如下（**严格按此粘贴**）：

```typescript
import backgroundTaskManager from '@kit.BackgroundTasksKit';
import { wantAgent, OperationType, Flags, common } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import notificationManager from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'BackgroundTaskCoordinator';
const NOTIFICATION_ID = 1001;
const NOTIFICATION_TITLE = '正在生成分镜';
const NOTIFICATION_TEXT = '点击返回应用查看进度';

/**
 * 申请 / 释放鸿蒙长时后台任务。
 *
 * - 仅供 EntryAbility.onBackground 触发申请；onForeground 触发释放。
 * - 重复 acquire / release 是 no-op，避免多次申请导致系统拒绝。
 * - 申请失败仅 hilog warn，不抛错——前台任务正常运行，不被后台保护失败阻断。
 */
export class BackgroundTaskCoordinator {
  private static activeContext: common.UIAbilityContext | null = null;
  private static wantAgentInstance: WantAgent | null = null;

  static isActive(): boolean {
    return BackgroundTaskCoordinator.activeContext !== null;
  }

  static async acquire(context: common.UIAbilityContext): Promise<void> {
    if (BackgroundTaskCoordinator.isActive()) {
      hilog.info(DOMAIN, TAG, 'background task already acquired, skip');
      return;
    }
    BackgroundTaskCoordinator.activeContext = context;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [Flags.UPDATE_PRESENT_FLAG]
      };
      BackgroundTaskCoordinator.wantAgentInstance =
        await wantAgent.getWantAgent(wantAgentInfo);

      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        BackgroundTaskCoordinator.wantAgentInstance
      );

      await BackgroundTaskCoordinator.publishNotification();
      hilog.info(DOMAIN, TAG, 'background task acquired');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'acquire failed: %{public}s', JSON.stringify(e));
      BackgroundTaskCoordinator.activeContext = null;
      BackgroundTaskCoordinator.wantAgentInstance = null;
    }
  }

  static async release(context: common.UIAbilityContext): Promise<void> {
    if (!BackgroundTaskCoordinator.isActive()) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', JSON.stringify(e));
    }
    await BackgroundTaskCoordinator.cancelNotification();
    BackgroundTaskCoordinator.activeContext = null;
    BackgroundTaskCoordinator.wantAgentInstance = null;
    hilog.info(DOMAIN, TAG, 'background task released');
  }

  private static async publishNotification(): Promise<void> {
    const want = BackgroundTaskCoordinator.wantAgentInstance;
    if (!want) {
      return;
    }
    try {
      const request: notificationManager.NotificationRequest = {
        id: NOTIFICATION_ID,
        content: {
          contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: NOTIFICATION_TITLE,
            text: NOTIFICATION_TEXT,
            wantAgent: want
          }
        }
      };
      await notificationManager.publish(request);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'publish notification failed: %{public}s', JSON.stringify(e));
    }
  }

  private static async cancelNotification(): Promise<void> {
    try {
      await notificationManager.cancel(NOTIFICATION_ID);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'cancel notification failed: %{public}s', JSON.stringify(e));
    }
  }
}
```

- [ ] **Step 2: 在 DevEco Studio 验证编译**

打开 DevEco Studio 加载 ZdramaHarmony 项目，触发一次 "Build Hap"。

预期：编译通过，无 TS 类型错误。

如果 `NotificationRequest` / `ContentType` / `NotificationBasicContent` / `WantAgent` 等类型找不到，可能需要：

- `WantAgent` 已经通过 `import type { WantAgent } from '@kit.AbilityKit';` 导入
- `NotificationRequest` 等如果在 `import notificationManager from '@kit.NotificationKit';` 后没解析到，追加 `import type { NotificationRequest, ContentType } from '@kit.NotificationKit';`
- 实际报错时按 DevEco Studio 的 `Quick Fix` 提示选择正确的 import 路径

- [ ] **Step 3: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/common/BackgroundTaskCoordinator.ets
git commit -m "feat(harmony): 新增 BackgroundTaskCoordinator 管理长时任务与通知"
```

---

## Task 3: `UseCases.ets` — 新增 `activeGeneratingProjects` 状态跟踪

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`（在 `class UseCases` 字段声明区附近）

**Interfaces:**
- Consumes: 无
- Produces:
  - `private static activeGeneratingProjects: Set<number>`
  - `static hasActiveGenerating(): boolean`
  - `private static markGenerating(projectId: number): void`
  - `private static unmarkGenerating(projectId: number): void`

- [ ] **Step 1: 在 `class UseCases` 静态字段区新增 Set**

打开 `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`，定位到 `export class UseCases {` 块内 `private static mp4Composer = new LocalMp4Composer();` 这一行之后、`private static hasNonEmptyLocalFile(...)` 之前。

在 `private static mp4Composer = new LocalMp4Composer();` 之后插入：

```typescript
  // 当前正在生成图片/视频的项目 ID 集合。
  // EntryAbility.onBackground 据此判断是否需要申请长时任务。
  private static activeGeneratingProjects: Set<number> = new Set();
```

- [ ] **Step 2: 新增三个静态方法**

在 `private static hasNonEmptyLocalFile(...)` 之前（也就是在 `activeGeneratingProjects` 字段声明**之后**），插入：

```typescript
  /** 是否存在正在生成图片/视频的项目（用于 EntryAbility 决定是否申请长时任务） */
  static hasActiveGenerating(): boolean {
    return UseCases.activeGeneratingProjects.size > 0;
  }

  private static markGenerating(projectId: number): void {
    UseCases.activeGeneratingProjects.add(projectId);
  }

  private static unmarkGenerating(projectId: number): void {
    UseCases.activeGeneratingProjects.delete(projectId);
  }
```

- [ ] **Step 3: 编译验证**

在 DevEco Studio 触发 Build Hap。

预期：编译通过；类内字段与方法声明位置无错。

- [ ] **Step 4: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "feat(harmony): UseCases 跟踪正在生成的项目 ID"
```

---

## Task 4: `UseCases.ets` — `generateStoryboardImages` 入口 try/finally

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`（line ~252-369 `generateStoryboardImages` 方法）

**Interfaces:**
- Consumes: Task 3 新增的 `markGenerating` / `unmarkGenerating`
- Produces: `generateStoryboardImages` 在入口 add / 出口 finally delete

- [ ] **Step 1: 在方法签名后插入 markGenerating**

打开 `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`，定位 `static async generateStoryboardImages(`。

在 `): Promise<TextResult> {` 这行**之后**、原 `const project = await UseCases.repo.getProject(projectId);` **之前**，插入：

```typescript
    UseCases.markGenerating(projectId);
    try {
```

- [ ] **Step 2: 在方法末尾（return 前）插入 finally**

定位 `generateStoryboardImages` 最后一个 return：

```typescript
    return { ok: false, value: '', error: firstError.length > 0 ? firstError : '图片生成失败' };
  }
```

在 `return { ok: false, ... }` 这行**之前**插入：

```typescript
    } finally {
      UseCases.unmarkGenerating(projectId);
    }
```

注意：此方法有 3 个 return 语句（2 个 `{ ok: true }` 和 1 个 `{ ok: false }`）。try 包住全部 3 个 return，finally 在最外层兜底。

**最终方法体结构示意**：

```typescript
  static async generateStoryboardImages(
    projectId: number,
    settings: AgnesSettings,
    onProgress?: GenerationProgressCallback
  ): Promise<TextResult> {
    UseCases.markGenerating(projectId);
    try {
      const project = await UseCases.repo.getProject(projectId);
      // ... 原 if (!project) return ...
      // ... 原 const shots = ... ...
      // ... 原 for (const shot of shots) { ... } ...
      // ... 原 await UseCases.repo.updateProjectTextResult(...)
      // ... 原 if (completed === shots.length) return { ok: true, value: '${generated}', error: '' }; ...
      // ... 原 if (generated > 0) return { ok: true, value: '${generated}', error: '' }; ...
      return { ok: false, value: '', error: firstError.length > 0 ? firstError : '图片生成失败' };
    } finally {
      UseCases.unmarkGenerating(projectId);
    }
  }
```

- [ ] **Step 3: 编译验证**

DevEco Studio 触发 Build Hap。预期：编译通过；缩进与原代码风格保持一致（2 空格）。

- [ ] **Step 4: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "feat(harmony): generateStoryboardImages 入口维护 activeGenerating"
```

---

## Task 5: `UseCases.ets` — `generateStoryboardVideos` 入口 try/finally

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`（line ~372-474 `generateStoryboardVideos` 方法）

**Interfaces:**
- Consumes: Task 3 新增的 `markGenerating` / `unmarkGenerating`
- Produces: `generateStoryboardVideos` 在入口 add / 出口 finally delete

- [ ] **Step 1: 在方法签名后插入 markGenerating**

定位 `static async generateStoryboardVideos(`。

在 `): Promise<TextResult> {` 这行**之后**、原 `const project = await UseCases.repo.getProject(projectId);` **之前**，插入：

```typescript
    UseCases.markGenerating(projectId);
    try {
```

- [ ] **Step 2: 在方法末尾（return 前）插入 finally**

定位最后一个 `return`：

```typescript
    return { ok: false, value: '', error: firstError.length > 0 ? firstError : '视频生成失败' };
  }
```

在 `return { ok: false, ... }` 这行**之前**插入：

```typescript
    } finally {
      UseCases.unmarkGenerating(projectId);
    }
```

**最终方法体结构示意**：

```typescript
  static async generateStoryboardVideos(
    projectId: number,
    settings: AgnesSettings,
    onProgress?: GenerationProgressCallback
  ): Promise<TextResult> {
    UseCases.markGenerating(projectId);
    try {
      const project = await UseCases.repo.getProject(projectId);
      // ... 原 if (!project) return ...
      // ... 原 const shots = ... ...
      // ... 原 for (const shot of shots) { ... } ...
      // ... 原 await UseCases.repo.updateProjectTextResult(...)
      // ... 原 if (completed === shots.length) return { ok: true, ... }; ...
      // ... 原 if (generated > 0) return { ok: true, ... }; ...
      return { ok: false, value: '', error: firstError.length > 0 ? firstError : '视频生成失败' };
    } finally {
      UseCases.unmarkGenerating(projectId);
    }
  }
```

- [ ] **Step 3: 编译验证**

DevEco Studio 触发 Build Hap。预期：编译通过；两个方法风格对称。

- [ ] **Step 4: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "feat(harmony): generateStoryboardVideos 入口维护 activeGenerating"
```

---

## Task 6: `EntryAbility.ets` — 接入 `onBackground` / `onForeground`

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/entryability/EntryAbility.ets`

**Interfaces:**
- Consumes:
  - `BackgroundTaskCoordinator.acquire(context)` / `release(context)`（Task 2）
  - `UseCases.hasActiveGenerating()`（Task 3）
- Produces: `onBackground` 在有活跃生成时申请长时任务；`onForeground` 直接释放

- [ ] **Step 1: 新增 import**

在 `ZdramaHarmony/entry/src/main/ets/entryability/EntryAbility.ets` 顶部（line 1-5 import 区域），在 `import { UseCases } from '../usecase/UseCases';` 之后**追加**：

```typescript
import { BackgroundTaskCoordinator } from '../common/BackgroundTaskCoordinator';
```

- [ ] **Step 2: 实现 `onBackground`**

定位当前 `onBackground(): void {` 下的空方法体。替换方法体为：

```typescript
  // 应用切换到后台时回调
  onBackground(): void {
    if (UseCases.hasActiveGenerating()) {
      BackgroundTaskCoordinator.acquire(this.context);
    }
  }
```

- [ ] **Step 3: 实现 `onForeground`**

定位当前 `onForeground(): void {` 下的空方法体。替换方法体为：

```typescript
  // 应用切换到前台时回调
  onForeground(): void {
    BackgroundTaskCoordinator.release(this.context);
  }
```

- [ ] **Step 4: 编译验证**

DevEco Studio 触发 Build Hap。预期：编译通过；3 个 import 全部解析成功。

- [ ] **Step 5: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat(harmony): onBackground 申请长时任务，onForeground 释放"
```

---

## Task 7: 端到端验证

**Files:**
- 无文件改动

**Interfaces:**
- Consumes: Task 1-6 全部产出
- Produces: 人工/真机确认 4 个验证场景通过

- [ ] **Step 1: 真机/模拟器跑通冷启动基本流**

1. 启动应用，进入一个有未完成图片生成的项目
2. 点"生成图片" → 正常开始生成（前台）
3. 等候 30 秒，所有分镜图片应正常生成完毕
4. 无崩溃，无 hilog error 出现

- [ ] **Step 2: 验证后台保护**

1. 启动应用，进入一个视频生成未完成的项目
2. 点"生成视频" → **立即按 Home 切到后台**
3. 通知中心应出现 "正在生成分镜" 通知
4. 等候 1 分钟后切回前台
5. 视频应继续生成（继续到下一个分镜）或已完成

- [ ] **Step 3: 验证前后台反复切换**

1. 启动应用，进入生成中
2. 切后台 1 秒 → 切前台 1 秒 → 切后台 1 秒 → 切前台 1 秒 → 重复 5 次
3. 检查 hilog：不应有重复 `acquire failed` 警告（重复 acquire 应当 no-op）
4. 最终生成仍能正常完成

- [ ] **Step 4: 验证冷启动 DB 兜底**

1. 启动应用，进入视频生成中
2. 立即切到后台
3. `adb shell am force-stop com.huobao.zdrama` 杀进程
4. 重新启动应用
5. 进入项目详情，应能看到 FAILED 提示（来自 `resetOrphanProcessingProjects` 在 `onCreate` 里的兜底）

- [ ] **Step 5: 提交验证记录（可选）**

如把 Step 1-4 的 hilog 关键日志片段（`background task acquired` / `background task released` / `acquire failed`）贴到一个文档或 issue 评论里，commit 如下：

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add -A  # 如果有验证报告文件
git commit -m "docs: 鸿蒙长时后台任务真机验证记录" || echo "无新文件，跳过"
```

---

## 风险与回退

- **DATA_TRANSFER 低速检测挂起**：视频轮询 10s 一次可能触发系统挂起；如挂起期间 HTTP 已断，UI 主线程 Promise 链在 await 处抛错，按 FAILED 流程处理；冷启动 `resetOrphanProcessingProjects` 兜底
- **长时任务超时（API 9 ~10 分钟）**：UI 主线程 Promise 链收到异常后标 FAILED；用户可重试
- **权限被拒**：`BackgroundTaskCoordinator.acquire` 失败仅 hilog warn；不影响前台生成
- **回退策略**：如需回退，git revert 全部 6 个 commit 即可
