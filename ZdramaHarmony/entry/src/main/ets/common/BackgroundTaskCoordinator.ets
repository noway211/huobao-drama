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
        wantAgent: want,
        content: {
          contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: NOTIFICATION_TITLE,
            text: NOTIFICATION_TEXT
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
