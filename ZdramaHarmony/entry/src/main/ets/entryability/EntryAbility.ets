import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../common/AppContext';
import { UseCases } from '../usecase/UseCases';
import { BackgroundTaskCoordinator } from '../common/BackgroundTaskCoordinator';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  // Ability 创建时回调：初始化应用上下文，并执行冷启动的孤儿项目状态恢复
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    // 将 ability 上下文提供给 数据层/设置层 使用。
    AppContext.init(this.context);
    // 冷启动恢复：将被中断的 PROCESSING 项目重置为 FAILED。
    UseCases.resetOrphanProcessingProjects()
      .then((n) => {
        if (n > 0) {
          hilog.info(DOMAIN, TAG, 'reset %{public}d orphan PROCESSING project(s)', n);
        }
      })
      .catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'orphan reset failed: %{public}s', JSON.stringify(e));
      });
  }

  // Ability 销毁时回调
  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  // 窗口 stage 创建时回调：加载首页内容 pages/Index
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  // 窗口 stage 销毁时回调
  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  // 应用切换到前台时回调
  onForeground(): void {
    BackgroundTaskCoordinator.release(this.context);
  }

  // 应用切换到后台时回调
  onBackground(): void {
    if (UseCases.hasActiveGenerating()) {
      BackgroundTaskCoordinator.acquire(this.context);
    }
  }
}
