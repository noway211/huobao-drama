# 鸿蒙端长时后台任务设计

## 背景

鸿蒙端（`ZdramaHarmony`）的图片与视频生成调用链目前跑在 UIAbility 的 UI 主线程上，HTTP 请求用 `http.createHttp()`，视频轮询用 `setTimeout` 10 秒一次、最长 60 次。

当用户切到后台（按 Home、锁屏、切换应用），HarmonyOS 系统会**强制打断**主线程上的 HTTP 请求和 setTimeout 定时器，UI 主线程上的 Promise 链直接进入异常状态：

- 图片生成中途断开 → 整批标记 FAILED，已下载的图片可能残留
- 视频轮询中途断开 → 拿不到完成的 `video_url`，用户切回前台时任务已"死"在内存里
- 项目数据库中残留 `status=PROCESSING` 的孤儿记录，需要冷启动时 `resetOrphanProcessingProjects` 兜底标 FAILED

`EntryAbility.onBackground` / `onForeground` 当前是空实现，没有利用 `backgroundTaskManager` 的长时任务能力。

## 目标

- 用户切到后台时，图片/视频生成与轮询不被系统打断
- 回到前台时任务自然继续，用户无感知
- UI 与数据库状态机不需重构

## 非目标

- 不修改图片/视频生成 API 协议
- 不修改 `UseCases.generateStoryboardImages` / `generateStoryboardVideos` 的对外签名与业务逻辑
- 不修改数据库 schema
- 不主动轮询或重试——若长时任务被系统挂起，回到前台后让 UI 主线程按原逻辑继续
- 不实现细粒度的"按分镜逐个申请"接力策略——一次性申请覆盖整批
- 不改 `EntryAbility.onCreate` 的 `resetOrphanProcessingProjects` 兜底逻辑

## 关键决策

| 项 | 决策 | 理由 |
|---|---|---|
| 长时任务模式 | `BackgroundMode.DATA_TRANSFER = 1` | 匹配 HTTP 上传/下载语义；用户已接受"低速检测挂起"风险 |
| 申请时机 | 仅 `onBackground` 触发时申请 | 前台不打扰用户，符合直觉 |
| 释放时机 | `onForeground` 触发时释放 | 回到前台后让任务在普通 UI 生命周期下跑完 |
| 任务范围 | 一次性覆盖所有进行中的项目生成 | 用户选择"高风险"——简化实现 |
| 通知 | 必带 WantAgent + 持续通知 | SDK 强制要求，否则 `startBackgroundRunning` 失败 |
| 失败回退 | 申请失败仅 warn 日志，不中断前台任务；长时任务被系统挂起时 UI 主线程 Promise 链按原异常处理 | 冷启动 `resetOrphanProcessingProjects` 兜底 |

## 涉及文件

### 新增

- `ZdramaHarmony/entry/src/main/ets/common/BackgroundTaskCoordinator.ets`

### 修改

- `ZdramaHarmony/entry/src/main/module.json5`
- `ZdramaHarmony/entry/src/main/ets/entryability/EntryAbility.ets`
- `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`

## 数据流

```
[用户在 ProjectDetailPage 点 "生成图片/视频"]
   └─► UseCases.generateStoryboardImages/Videos()         // UI 主线程
         ├─ UseCases.activeGeneratingProjects.add(projectId)
         ├─ for (shot) { image/video.generate(...) ; mediaDownload.download(...) }
         └─ finally { UseCases.activeGeneratingProjects.delete(projectId) }

[用户按 Home / 切到后台]
   └─► EntryAbility.onBackground()
         └─► if (UseCases.hasActiveGenerating())
                BackgroundTaskCoordinator.acquire(context, 'dataTransfer')
                  ├─ wantAgent.getWantAgent(...)        // 拉回前台的 WantAgent
                  ├─ backgroundTaskManager.startBackgroundRunning(
                  │      context, DATA_TRANSFER, wantAgent)
                  └─ notificationManager.publish(...)  // 常驻通知

[后台期间]
   └─► HTTP 请求 + 轮询 setTimeout 在 UI 主线程继续
       长时任务保活通知持续显示
       任务结束 → UseCases.activeGeneratingProjects.delete → UseCases.hasActiveGenerating() = false
       （不主动 stopBackgroundRunning，等用户切回前台）

[用户点通知 / 切回前台]
   └─► EntryAbility.onForeground()
         └─► BackgroundTaskCoordinator.release(context)
               ├─ backgroundTaskManager.stopBackgroundRunning(context)
               └─ notificationManager.cancel(...)
```

## 实现细节

### `module.json5`

新增两个字段：

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.GET_NETWORK_INFO" },
  { "name": "ohos.permission.KEEP_BACKGROUND_RUNNING" }   // 新增
],
"abilities": [{
  "name": "EntryAbility",
  ...
  "backgroundModes": ["dataTransfer"],                      // 新增
  ...
}]
```

### `common/BackgroundTaskCoordinator.ets`（新增）

封装长时任务申请/释放 + 通知发布/取消。导出两个静态方法：

```ts
import backgroundTaskManager from '@kit.BackgroundTasksKit';
import { wantAgent, OperationType, Flags, common } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import notificationManager from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'BackgroundTaskCoordinator';
const NOTIFICATION_ID = 1001;

export class BackgroundTaskCoordinator {
  private static activeContext: common.UIAbilityContext | null = null;
  private static wantAgentInstance: WantAgent | null = null;

  /** 当前是否已经申请过 */
  static isActive(): boolean {
    return BackgroundTaskCoordinator.activeContext !== null;
  }

  /** 申请长时任务；重复申请直接返回。 */
  static async acquire(context: common.UIAbilityContext): Promise<void> {
    if (BackgroundTaskCoordinator.isActive()) {
      hilog.info(DOMAIN, TAG, 'background task already acquired, skip');
      return;
    }
    BackgroundTaskCoordinator.activeContext = context;
    try {
      // 1. 拉回前台的 WantAgent
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

      // 2. 申请长时任务
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        BackgroundTaskCoordinator.wantAgentInstance
      );

      // 3. 持续通知
      await BackgroundTaskCoordinator.publishNotification();
      hilog.info(DOMAIN, TAG, 'background task acquired');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'acquire failed: %{public}s', JSON.stringify(e));
      BackgroundTaskCoordinator.activeContext = null;
      BackgroundTaskCoordinator.wantAgentInstance = null;
    }
  }

  /** 释放长时任务。已释放时直接返回。 */
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
    if (!want) return;
    // 通知渠道（API 9+）需要先 ensureSlot；channelId='zdrama_generating'
    const notificationRequest: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      content: {
        contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '正在生成分镜',
          text: '点击返回应用查看进度',
          wantAgent: want
        }
      }
    };
    await notificationManager.publish(notificationRequest);
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

> 通知渠道需要先调用 `notificationManager.addSlot` 注册，但本项目之前未注册任何 slot——本设计不引入 slot 注册改动，沿用系统默认 channel（API 9 行为）。

### `entryability/EntryAbility.ets`（修改）

```ts
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';   // 仅用于类型；不直接调用
import { BackgroundTaskCoordinator } from '../common/BackgroundTaskCoordinator';
import { UseCases } from '../usecase/UseCases';

export default class EntryAbility extends UIAbility {
  // onCreate / onDestroy / onWindowStageCreate / onWindowStageDestroy 保持不变
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 保留：AppContext.init + resetOrphanProcessingProjects
  }
  onDestroy(): void { /* 保持空 */ }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', ...);  // 保持不变
  }
  onWindowStageDestroy(): void { /* 保持空 */ }

  onForeground(): void {
    BackgroundTaskCoordinator.release(this.context);
  }

  onBackground(): void {
    if (UseCases.hasActiveGenerating()) {
      BackgroundTaskCoordinator.acquire(this.context);
    }
  }
}
```

### `usecase/UseCases.ets`（修改）

仅新增 1 个 Set 和 2 个静态方法，业务逻辑零改动：

```ts
// 类外或 UseCases 静态字段上
private static activeGeneratingProjects: Set<number> = new Set();

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

在 `generateStoryboardImages` 入口（line ~252，紧接方法签名后）：

```ts
static async generateStoryboardImages(
  projectId: number,
  settings: AgnesSettings,
  onProgress?: GenerationProgressCallback
): Promise<TextResult> {
  UseCases.markGenerating(projectId);
  try {
    const project = await UseCases.repo.getProject(projectId);
    // ... 原有所有逻辑保持不变
  } finally {
    UseCases.unmarkGenerating(projectId);
  }
}
```

在 `generateStoryboardVideos` 入口（line ~372）同样包一层 try/finally。

注意：当前两个方法都**没有外层 try/catch**，需要新加 try/finally 块。这是最小侵入方式——不重写任何业务逻辑。

## 错误处理

| 场景 | 行为 |
|---|---|
| `acquire()` 内部 `startBackgroundRunning` 抛错（权限拒绝、通知未授权） | catch + warn 日志；不重试；前台任务不受影响，正常跑完 |
| `release()` 内部 `stopBackgroundRunning` 抛错（任务已被系统停止） | catch + warn；不影响其他清理逻辑 |
| 申请后 10 分钟（API 9 长时任务上限）任务被系统回收 | UI 主线程 Promise 链按原异常处理；DB 状态保留；冷启动 `resetOrphanProcessingProjects` 标 FAILED |
| DATA_TRANSFER 低速检测挂起任务 | 任务进入挂起态；用户切回前台 `release()` 调用后 UI 主线程继续；DB 状态保留；如挂起期间 HTTP 已断开，UI 主线程 Promise 链在 await 处抛错，按 FAILED 流程处理 |
| 重复 `acquire` | 内部 `isActive()` 检查直接返回，避免重复申请 |
| 重复 `release` | 内部 `isActive()` 检查直接返回 |

## 风险

| 风险 | 概率 | 缓解 |
|---|---|---|
| DATA_TRANSFER 低速检测挂起（视频轮询 10s 一次） | 高 | 用户已接受；若挂起期间 HTTP 已断，UI 主线程后续 await 抛错走 FAILED 流程；冷启动兜底 |
| 长时任务单次最长时长不足以覆盖 5-10 个分镜 | 中 | UI 主线程 Promise 链收到异常后标 FAILED；用户可重试 |
| `KEEP_BACKGROUND_RUNNING` 权限被拒 | 低 | `acquire()` 失败仅 warn；不影响前台生成 |
| 应用被系统强杀 | 中 | DB 状态保留；冷启动 `resetOrphanProcessingProjects` 提示用户 |
| WantAgent 创建抛错 | 极低 | catch + warn；等同于 acquire 失败 |

## 验证

### 单元层

- `BackgroundTaskCoordinator.acquire/release` 在 `acquire` 两次调用时只真正申请一次
- `UseCases.hasActiveGenerating` 在 generate 入口 add 后立即返回 true，finally 后返回 false

### 端到端

1. **基本后台保护**：
   - 打开一个未完成的图片生成项目
   - 点 "生成图片" → 立即按 Home
   - 通知中心出现"正在生成分镜"通知
   - 等 30 秒 → 切回前台 → 任务完成，所有分镜图片已生成

2. **视频轮询真保护**：
   - 打开一个未完成的视频生成项目
   - 点 "生成视频" → 立即按 Home
   - 锁屏 5 分钟
   - 解锁 → 切回应用 → 视频已生成完（或进度推进到第 30 个分镜）

3. **前后台反复切换**：
   - 点 "生成" → 切后台 1s → 切前台 1s → 切后台 1s → ... → 不出现 hilog 报错

4. **权限拒绝回退**：
   - 在系统设置中关闭 "后台运行" 权限
   - 切后台 → 通知不出现 → 切回前台 → 任务可能 FAILED（正常）
   - logcat 看到 `acquire failed` warn 日志

5. **DB 兜底**：
   - 切后台跑生成中 → `adb shell am force-stop com.huobao.zdrama`
   - 重启应用 → 进入项目详情 → 看到 FAILED 提示（来自 `resetOrphanProcessingProjects`）
