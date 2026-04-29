/**
 * Index 页面 - 应用启动页
 * 等待 AppStore 初始化完成后，根据认证状态跳转到 LoginPage 或 MainPage
 */

import { appStore } from '../store/AppStore'
import { AppColors } from '../common/Constants'
import router from '@ohos.router'

@Entry
@Component
struct Index {
  @StorageProp('themeName') themeName: string = 'original'

  aboutToAppear(): void {
    this.waitAndRoute()
  }

  private waitAndRoute(): void {
    if (appStore.auth.initialized) {
      if (appStore.auth.isAuthenticated) {
        router.replaceUrl({ url: 'pages/MainPage' })
      } else {
        router.replaceUrl({ url: 'pages/LoginPage' })
      }
    } else {
      // 初始化尚未完成，轮询等待（每 50ms 检查一次）
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
    .backgroundColor(AppColors.white)
  }
}
