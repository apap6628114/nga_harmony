import { UIContext } from '@ohos.arkui.UIContext'
import { appStore } from '../store/AppStore'
import { invalidateServerSession } from './api/AuthApi'
import { Logger, DOMAIN_SERVICE, formatError } from '../common/utils/Logger'

const logger = new Logger(DOMAIN_SERVICE, 'LogoutOrchestrator')

/**
 * 退出登录流程编排器。
 *
 * 集中编排"服务端登出 → 本地清理 → 导航跳转"完整流程。
 * 调用方（@Component）传入 UIContext 用于导航。
 * 服务端登出失败不阻塞本地清理。
 */
export class LogoutOrchestrator {
  async logout(context: UIContext): Promise<void> {
    const token = appStore.auth.token
    // 1. 服务端登出（纯 API，不碰 Store，失败不阻塞）
    if (token) {
      try {
        await invalidateServerSession(token)
      } catch (e) {
        logger.warn('服务端登出失败: %{public}s', formatError(e))
      }
    }
    // 2. 本地清理（AppStore.clearAuth 内部编排全部 Store reset）
    appStore.clearAuth()
    // 3. 导航到登录页
    try {
      context.getRouter().replaceUrl({ url: 'pages/LoginPage' })
    } catch (e) {
      logger.error('导航到登录页失败: %{public}s', formatError(e))
    }
  }
}

export const logoutOrchestrator = new LogoutOrchestrator()
