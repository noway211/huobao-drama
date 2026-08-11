# 鸿蒙长时后台任务 — 端到端验证报告

> 计划文件: [docs/superpowers/plans/2026-08-11-harmony-background-long-task.md](../plans/2026-08-11-harmony-background-long-task.md)
> 范围: Task 1 (module.json5) → Task 6 (EntryAbility 接入),共 6 个 commit
> 状态: **静态检查全部通过;真机 4 场景待用户手测**

## 1. 静态检查 (已完成)

以下静态不变量在 shell 端可验证,已确认通过。

### 1.1 module.json5 声明 (Task 1, commit 2060076)

- [x] `ohos.permission.KEEP_BACKGROUND_RUNNING` 已加入 `requestPermissions` (line 47)
- [x] `backgroundModes: ["dataTransfer"]` 已加入 EntryAbility (lines 24-26)
- [x] `JSON.parse` 通过 → JSON5 结构合法

### 1.2 BackgroundTaskCoordinator (Task 2, commit ceb5cdf,fix round 1)

- [x] `acquire` 在已激活时直接 return (line 29-32) → 重复 acquire no-op
- [x] `release` 在未激活时直接 return (line 63-65) → 重复 release no-op
- [x] `NotificationRequest.wantAgent` 位于顶层 (line 85),**不在** `content.normal` 内 (line 88-91 只有 title/text)
- [x] 申请/释放失败仅 `hilog.warn` (line 56/69),不抛错
- [x] 异常路径会清空 `activeContext` / `wantAgentInstance` (line 57-58),避免状态污染

### 1.3 UseCases 状态跟踪 (Task 3, commit dd69007)

- [x] `activeGeneratingProjects: Set<number>` 字段存在 (UseCases.ets:51)
- [x] `hasActiveGenerating()` / `markGenerating(id)` / `unmarkGenerating(id)` 三个静态方法已加 (UseCases.ets:54-64)
- [x] `markGenerating` 调用点:2 处,分别在两个生成方法入口 (line 274 / 399)
- [x] `unmarkGenerating` 调用点:2 处,分别在两个生成方法 finally 内 (line 389 / 499)

### 1.4 try/finally 包裹 (Task 4, Task 5, commits 7c6da20 / 23bed86)

- [x] `generateStoryboardImages`: `markGenerating` 在 try 前 (line 274),`unmarkGenerating` 在 finally 内 (line 389)
- [x] `generateStoryboardVideos`: `markGenerating` 在 try 前 (line 399),`unmarkGenerating` 在 finally 内 (line 499);**最后一个 return 在 try 内** (line 497),与 Task 4 结构对称
- [x] 两个方法的所有 5 个 return 均在 try 内,finally 在每个出口都执行

### 1.5 EntryAbility 接入 (Task 6, commit 633ed91)

- [x] `import { BackgroundTaskCoordinator } from '../common/BackgroundTaskCoordinator';` 已加 (EntryAbility.ets:6)
- [x] `onBackground` 用 `hasActiveGenerating()` 守卫,有活跃任务时才 acquire (EntryAbility.ets:55-60)
- [x] `onForeground` 无条件 release (EntryAbility.ets:50-53)
- [x] `this.context` 在 UIAbility 生命周期中可用,类型与 `common.UIAbilityContext` 兼容

### 1.6 完整 commit 链 (按时间顺序)

```
2060076  Task 1: module.json5 加权限与后台模式
ceb5cdf  Task 2: 新增 BackgroundTaskCoordinator 管理长时任务与通知 (含 fix round 1)
dd69007  Task 3: UseCases 跟踪正在生成的项目 ID
7c6da20  Task 4: generateStoryboardImages 入口维护 activeGenerating
23bed86  Task 5: generateStoryboardVideos 入口维护 activeGenerating (含 fix round 1)
633ed91  Task 6: onBackground 申请长时任务,onForeground 释放
```

## 2. 真机验证场景 (待人工执行)

DevEco Studio + 真机/远程模拟器为唯一可执行环境。预期总耗时 30-60 分钟,需要 1 个未完成的项目(图片或视频)和 1 个能 adb 的环境。

### 场景 1: 冷启动基本流(无后台保护)

**目的**: 验证 Task 1-5 的代码改动不破坏前台基本生成流程。

| 步骤 | 操作 | 预期结果 |
|---|---|---|
| 1 | 启动应用,进入一个有未完成图片生成的项目 | 项目页正常打开 |
| 2 | 点 "生成图片" | 前台开始生成,进度回调正常 |
| 3 | 等候 30 秒 | 所有分镜图片生成完毕,UI 显示 COMPLETED |
| 4 | 检查 `hilog` | 无 ERROR,无 `acquire failed` / `release failed` 警告 |

**关键日志关键词**:
- `generateStoryboardImages start: project=... shots=...`
- `image API OK for shot #...`
- `download OK for shot #...`
- 无 `acquire failed` 出现(因为没有切后台)

### 场景 2: 后台保护(核心场景)

**目的**: 验证视频生成切到后台时不被系统杀掉,且用户能看到通知。

| 步骤 | 操作 | 预期结果 |
|---|---|---|
| 1 | 启动应用,进入一个视频生成未完成的项目(分镜 >= 2) | 项目页正常打开 |
| 2 | 点 "生成视频" | 立即按 Home 切到后台 |
| 3 | 下拉通知中心 | 出现通知: 标题 "正在生成分镜", 文本 "点击返回应用查看进度" |
| 4 | 等候 1 分钟 | 通知持续存在,不消失 |
| 5 | 切回前台 | 视频应继续生成(继续到下一个分镜)或已完成 |
| 6 | 切前台后下拉通知中心 | 通知消失(因为 `onForeground` 触发了 `release` → `cancelNotification`) |

**关键日志关键词**:
- `background task acquired`(切后台后立即出现)
- `video API OK for shot #...`(持续出现,证明后台在跑)
- `background task released`(切回前台时出现)
- 通知 id = 1001

### 场景 3: 反复前后台切换(幂等性)

**目的**: 验证 `acquire` / `release` 的幂等性,不因为快速切换导致系统拒绝或状态错乱。

| 步骤 | 操作 | 预期结果 |
|---|---|---|
| 1 | 启动应用,进入生成中 | 正常 |
| 2 | 切后台 1 秒 → 切前台 1 秒,重复 5 次 | 每次切前台通知消失;切后台通知出现 |
| 3 | 检查 `hilog` 中 `acquire failed` 警告 | **不应**出现重复 `acquire failed`(重复 acquire 应当 `background task already acquired, skip`) |
| 4 | 等待最终生成 | 仍能正常完成,所有分镜进入 COMPLETED |

**关键日志关键词**:
- `background task already acquired, skip`(重复 acquire 时多次出现)
- `background task released`(每次切前台时)
- 无 `acquire failed` 或 `stopBackgroundRunning failed`

### 场景 4: 冷启动 DB 兜底

**目的**: 验证 `resetOrphanProcessingProjects` 在 `onCreate` 里的兜底,把被强杀的 PROCESSING 项目标 FAILED。

| 步骤 | 操作 | 预期结果 |
|---|---|---|
| 1 | 启动应用,进入视频生成中 | 正常 |
| 2 | 立即切到后台 | 触发 `acquire` |
| 3 | `adb shell am force-stop com.huobao.zdrama` | 进程被强杀 |
| 4 | 重新启动应用 | 启动后 `onCreate` 里的 `resetOrphanProcessingProjects` 执行 |
| 5 | 检查 `hilog` | 出现 `reset N orphan PROCESSING project(s)` |
| 6 | 进入项目详情 | 状态显示 FAILED,带错误信息 |

**关键日志关键词**:
- `reset N orphan PROCESSING project(s)`(N >= 1)
- 重新启动后,DB 中对应 `projects.current_stage` 不再是 VIDEO/PROCESSING,而是 FAILED

## 3. 风险与回退

- **DATA_TRANSFER 低速检测挂起**: 视频轮询 10s 一次可能触发系统挂起(API 9+);挂起期间 HTTP 已断,UI 主线程 Promise 链在 await 处抛错,按 FAILED 流程处理;冷启动 `resetOrphanProcessingProjects` 兜底
- **长时任务超时(API 9 ~10 分钟)**: UI 主线程 Promise 链收到异常后标 FAILED;用户可重试
- **权限被拒**: `BackgroundTaskCoordinator.acquire` 失败仅 hilog warn,不影响前台生成
- **回退策略**: `git revert 633ed91 23bed86 7c6da20 dd69007 ceb5cdf 2060076` 即可完整回退

## 4. 执行结果

| 场景 | 状态 | 执行人 | 日期 | 备注 |
|---|---|---|---|---|
| 场景 1: 冷启动基本流 | ⏳ 待执行 | | | |
| 场景 2: 后台保护 | ⏳ 待执行 | | | |
| 场景 3: 反复切换 | ⏳ 待执行 | | | |
| 场景 4: 冷启动兜底 | ⏳ 待执行 | | | |

## 5. 已知次要项 (deferred Minor)

- `generateStoryboardVideos` 的 `} finally {` 缩进为 2-space,与 `try {`(4-space)不匹配;方法体 indent 也是 4-space(Task 4 是 6-space)。纯 cosmetic,无功能影响;修复需要整个 method 重 indent,违反 "no reformat" 规则。详细见 `.superpowers/sdd/2026-08-11-harmony-background-long-task/progress.md` Task 5 minor 项
