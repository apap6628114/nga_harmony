import { connection } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { KEY_NETWORK_CHANGE_VERSION } from '../constants/AppStorageKeys'
import { bumpAppStorageVersion } from '../utils/AppStorageVersion'

const DOMAIN: number = 0x0000
const TAG: string = 'NetworkMonitor'

let netConnection: connection.NetConnection | null = null
let started: boolean = false

export function startNetworkMonitor(): void {
  if (started) {
    return
  }
  started = true
  try {
    netConnection = connection.createNetConnection()
    netConnection.on('netAvailable', (data: connection.NetHandle): void => {
      bumpAppStorageVersion(KEY_NETWORK_CHANGE_VERSION)
      hilog.info(DOMAIN, TAG, 'netAvailable netId=%{public}d', data.netId)
    })
    netConnection.on('netCapabilitiesChange', (data: connection.NetCapabilityInfo): void => {
      bumpAppStorageVersion(KEY_NETWORK_CHANGE_VERSION)
      hilog.info(DOMAIN, TAG, 'netCapabilitiesChange netId=%{public}d', data.netHandle.netId)
    })
    netConnection.on('netLost', (): void => {
      bumpAppStorageVersion(KEY_NETWORK_CHANGE_VERSION)
      hilog.info(DOMAIN, TAG, 'netLost')
    })
    netConnection.register((err: BusinessError): void => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'register error: %{public}s', JSON.stringify(err))
      } else {
        hilog.info(DOMAIN, TAG, 'registered')
      }
    })
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'startNetworkMonitor error: %{public}s', JSON.stringify(e))
  }
}
