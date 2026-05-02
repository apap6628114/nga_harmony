import { webview } from '@kit.ArkWeb'
import { PanelNavBar } from '../common/PanelNavBar'
import { routerStore } from '../store/RouterStore'
import { getSession } from '../service/NgaApi'
import { appStore } from '../store/AppStore'
import { ngaClient } from '../service/NgaClient'

@Component
export struct WebViewPanel {
  @Prop url: string = ''
  private controller: webview.WebviewController = new webview.WebviewController()
  @State pageTitle: string = ''

  aboutToAppear(): void {
    this.injectCookies()
  }

  private injectCookies(): void {
    if (!appStore.auth.isAuthenticated) {
      return
    }
    const session = getSession(appStore.auth.token)
    if (!session) {
      return
    }
    const baseUrl: string = ngaClient.getActiveDomain()
    try {
      webview.WebCookieManager.setCookie(baseUrl, 'ngaPassportUid=' + session.uid + '; Path=/')
      webview.WebCookieManager.setCookie(baseUrl, 'ngaPassportCid=' + session.cid + '; Path=/')
    } catch (e) {
      console.error('[WebViewPanel] setCookie failed: ' + JSON.stringify(e))
    }
  }

  build() {
    Column() {
      PanelNavBar({
        title: this.pageTitle || 'NGA网页版',
        onBack: (): void => {
          routerStore.back()
        }
      })

      Web({ src: this.url, controller: this.controller })
        .layoutWeight(1).width('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .geolocationAccess(true)
        .onTitleReceive((event: Object): void => {
          const evt = event as Record<string, Object>
          this.pageTitle = String(evt['title'] ?? '')
        })
    }
    .width('100%').height('100%')
  }
}