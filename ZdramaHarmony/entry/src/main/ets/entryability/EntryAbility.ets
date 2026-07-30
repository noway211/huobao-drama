import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../common/AppContext';
import { UseCases } from '../usecase/UseCases';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    // Make the ability context available to the data/settings layers.
    AppContext.init(this.context);
    // Cold-start recovery: interrupted PROCESSING projects → FAILED.
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

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
