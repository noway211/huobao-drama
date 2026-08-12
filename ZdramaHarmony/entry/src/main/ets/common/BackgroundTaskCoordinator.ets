import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'BackgroundTaskCoordinator';

/**
 * 申请 / 释放鸿蒙长时后台任务。
 *
 * - 仅供 EntryAbility.onBackground 触发申请；onForeground 触发释放。
 * - 重复 acquire / release 是 no-op，避免多次申请导致系统拒绝。
 * - 申请失败仅 hilog warn，不抛错——前台任务正常运行，不被后台保护失败阻断。
 * - 持久通知由系统在 startBackgroundRunning 调用后自动生成（携带 wantAgent，点击回到应用）。
 */
export class BackgroundTaskCoordinator {
  private static activeContext: common.UIAbilityContext | null = null;

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
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const wantAgentObj = await wantAgent.getWantAgent(wantAgentInfo);

      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        wantAgentObj
      );

      hilog.info(DOMAIN, TAG, 'background task acquired');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'acquire failed: %{public}s', JSON.stringify(e));
      BackgroundTaskCoordinator.activeContext = null;
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
    BackgroundTaskCoordinator.activeContext = null;
    hilog.info(DOMAIN, TAG, 'background task released');
  }
}
