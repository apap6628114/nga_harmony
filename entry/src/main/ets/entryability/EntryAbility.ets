import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { sessionStore } from '../service/SessionStore';
import { appStore } from '../store/AppStore';
import { browseHistoryStore } from '../store/BrowseHistoryStore';
import { voteRecordStore } from '../store/VoteRecordStore';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private curBp: string = 'sm'

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    // 初始化 SessionStore 和 AppStore（异步，Index 页面会等待 initialized 标志）
    Promise.all([sessionStore.init(this.context), appStore.init(this.context), browseHistoryStore.init(this.context), voteRecordStore.init(this.context)])
      .then(() => {
        hilog.info(DOMAIN, TAG, 'All stores initialized');
      })
      .catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'Store init failed: %{public}s', JSON.stringify(e));
      });

    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      try {
        const mainWindow = windowStage.getMainWindowSync()

        mainWindow.setWindowLayoutFullScreen(true)

        const sysBarProps: window.SystemBarProperties = {
          statusBarColor: '#00000000',
          statusBarContentColor: '#000000',
          navigationBarColor: '#00000000',
          navigationBarContentColor: '#000000'
        }
        mainWindow.setWindowSystemBarProperties(sysBarProps)

        const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        const density = display.getDefaultDisplaySync().densityPixels
        const topInset = avoidArea.topRect.height / density
        const bottomInset = avoidArea.bottomRect.height / density
        AppStorage.setOrCreate('statusBarHeight', topInset)
        AppStorage.setOrCreate('navBarHeight', bottomInset)

        this.updateBreakpoint(mainWindow.getWindowProperties().windowRect.width)
        mainWindow.on('windowSizeChange', (size: window.Size) => {
          this.updateBreakpoint(size.width)
        })
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Failed to setup immersive mode. Cause: %{public}s', JSON.stringify(e))
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    appStore.autoCheckinIfNeeded();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // 应用进入后台时持久化会话，防止被系统杀死后丢失
    sessionStore.flushNow();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  private updateBreakpoint(windowWidth: number): void {
    const densityPixels = display.getDefaultDisplaySync().densityPixels
    const widthVp = windowWidth / densityPixels
    let newBp: string = 'sm'
    if (widthVp < 600) {
      newBp = 'sm'
    } else if (widthVp < 840) {
      newBp = 'md'
    } else {
      newBp = 'lg'
    }
    if (this.curBp !== newBp) {
      this.curBp = newBp
      AppStorage.setOrCreate('currentBreakpoint', newBp)
      hilog.info(DOMAIN, TAG, 'Breakpoint changed to: %{public}s (%{public}f vp)', newBp, widthVp)
    }
  }
}
