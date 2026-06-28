import { connection } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { KEY_NETWORK_CHANGE_VERSION } from '../constants/AppStorageKeys'
import { bumpAppStorageVersion } from '../utils/AppStorageVersion'
import { Logger, DOMAIN_NETWORK, formatError } from '../utils/Logger'

const logger = new Logger(DOMAIN_NETWORK, 'NetworkMonitor')

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
      logger.info( 'netAvailable netId=%{public}d', data.netId)
    })
    netConnection.on('netCapabilitiesChange', (data: connection.NetCapabilityInfo): void => {
      bumpAppStorageVersion(KEY_NETWORK_CHANGE_VERSION)
      logger.info( 'netCapabilitiesChange netId=%{public}d', data.netHandle.netId)
    })
    netConnection.on('netLost', (): void => {
      bumpAppStorageVersion(KEY_NETWORK_CHANGE_VERSION)
      logger.info( 'netLost')
    })
    netConnection.register((err: BusinessError): void => {
      if (err) {
        logger.warn( 'register error: %{public}s', formatError(err))
      } else {
        logger.info( 'registered')
      }
    })
  } catch (e) {
    logger.warn( 'startNetworkMonitor error: %{public}s', formatError(e))
  }
}
