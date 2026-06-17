import { connection } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ImageLoadStrategy } from '../constants/Constants'

const DOMAIN: number = 0x0000
const TAG: string = 'NetworkUtil'

export function isWifiConnected(): boolean {
  try {
    let netHandle: connection.NetHandle = connection.getDefaultNetSync()
    if (netHandle.netId === 0) {
      return false
    }
    let netCap: connection.NetCapabilities = connection.getNetCapabilitiesSync(netHandle)
    if (netCap.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
      return false
    }
    return true
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'isWifiConnected error: %{public}s', JSON.stringify(e))
    return false
  }
}

/**
 * 判断当前图片加载策略下是否应使用"被动加载"（不主动请求图片/视频/头像）。
 *
 * ALWAYS → 主动；MANUAL → 被动；WIFI_ONLY → 视当前网络。
 * 由图片、视频、头像三类媒体组件共用，保证行为一致。
 *
 * @param strategy 图片加载策略值（ImageLoadStrategy.ALWAYS / MANUAL / WIFI_ONLY）
 * @returns true=被动（占位 / 黑屏 / 首字母），false=主动（直接加载）
 */
export function shouldUsePassive(strategy: string): boolean {
  if (strategy === ImageLoadStrategy.ALWAYS) return false
  if (strategy === ImageLoadStrategy.MANUAL) return true
  return !isWifiConnected()
}
