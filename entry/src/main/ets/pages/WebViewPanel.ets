import { webview } from '@kit.ArkWeb'
import { PanelNavBar } from '../common/components/PanelNavBar'
import { routerStore } from '../store/RouterStore'
import { getSession, getActiveDomain } from '../service/NgaApi'
import { appStore } from '../store/AppStore'
import { Logger, DOMAIN_UI, formatError } from '../common/utils/Logger'

const logger = new Logger(DOMAIN_UI, 'WebViewPanel')

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
    const baseUrl: string = getActiveDomain()
    try {
      webview.WebCookieManager.configCookieSync(baseUrl, 'ngaPassportUid=' + session.uid + '; Path=/')
      webview.WebCookieManager.configCookieSync(baseUrl, 'ngaPassportCid=' + session.cid + '; Path=/')
    } catch (e) {
      logger.error('[WebViewPanel] setCookie failed: %{public}s', formatError(e))
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
        .zoomAccess(true)
        .overviewModeAccess(true)
        .onControllerAttached(() => {
          try {
            this.controller.setCustomUserAgent('Mozilla/5.0 (Linux; Android 10; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36')
          } catch (e) { logger.error('setCustomUserAgent failed: %{public}s', (e as Error).message) }
        })
        .onTitleReceive((event: Object): void => {
          const evt = event as Record<string, Object>
          this.pageTitle = String(evt['title'] ?? '')
        })
    }
    .width('100%').height('100%')
  }
}