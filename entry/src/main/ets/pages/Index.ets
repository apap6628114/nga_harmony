/**
 * Index 页面 - 应用启动页
 * 等待 AppStore 初始化完成后，根据认证状态跳转到 LoginPage 或 MainPage
 */

import { appStore } from '../store/AppStore'
import { AppColors } from '../common/constants/Constants'
import { verifyToken } from '../service/NgaApi'
import { Logger, DOMAIN_UI } from '../common/utils/Logger'

const logger = new Logger(DOMAIN_UI, 'IndexPage')


@Entry
@Component
struct Index {
  @StorageProp('themeName') themeName: string = 'original'

  aboutToAppear(): void {
    this.waitAndRoute()
  }

  private async waitAndRoute(): Promise<void> {
    if (appStore.auth.initialized) {
      if (appStore.auth.isAuthenticated) {
        const valid = await verifyToken(appStore.auth.token)
        if (valid) {
          try { this.getUIContext().getRouter().replaceUrl({ url: 'pages/MainPage' }) } catch (e) { logger.error('route to MainPage failed: %{public}s', (e as Error).message) }
        } else {
          appStore.clearAuth()
          try { this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' }) } catch (e) { logger.error('route to LoginPage failed: %{public}s', (e as Error).message) }
        }
      } else {
        try { this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' }) } catch (e) { logger.error('route to LoginPage failed: %{public}s', (e as Error).message) }
      }
    } else {
      setTimeout(() => this.waitAndRoute(), 50)
    }
  }

  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(AppColors.primary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.bg)
  }
}
