import { getNotifications } from '../service/NgaApi'
import { BaseStore } from './BaseStore'
import { PreferencesStore } from '../common/infra/PreferencesStore'
import { SerialQueue } from '../common/infra/SerialQueue'
import { KEY_UNREAD_NOTI_COUNT } from '../common/constants/AppStorageKeys'
import type { NgaNotification } from '../model/Notification'
import type { AuthState } from './AuthStore'

/**
 * 通知缓存与未读数管理
 */
export class NotificationStore extends BaseStore<Object> {
  override state: Object = new Object()
  unreadNotiCount: number = 0
  private cachedNotifications: NgaNotification[] = []
  private lastNotiQueryTime: number = 0
  private static readonly NOTI_QUERY_DELAY: number = 30 * 1000

  async init(store: PreferencesStore, queue: SerialQueue, auth: AuthState): Promise<void> {
    this.setDeps(store, queue, auth)
    if (auth.uid) {
      await this.loadCachedNotifications()
    }
  }

  /** 重置缓存（登出时调用） */
  reset(): void {
    this.cachedNotifications = []
    this.unreadNotiCount = 0
    this.lastNotiQueryTime = 0
    super.reset()
  }

  // ============== Refresh ==============

  async refreshUnreadCount(): Promise<void> {
    if (!this.auth.isAuthenticated) return
    const now: number = Date.now()
    if (now - this.lastNotiQueryTime < NotificationStore.NOTI_QUERY_DELAY) return
    this.lastNotiQueryTime = now
    try {
      const result = await getNotifications(this.auth.token)
      if (result.ok && result.data && result.data.length > 0) {
        let unreadCount: number = 0
        for (let i: number = 0; i < result.data.length; i++) {
          if (result.data[i].unread) {
            unreadCount++
          }
        }
        this.unreadNotiCount = unreadCount
        AppStorage.setOrCreate(KEY_UNREAD_NOTI_COUNT, this.unreadNotiCount)
        this.cachedNotifications = result.data
        this.persistCachedNotifications()
      }
    } catch (e) {}
  }

  // ============== Cache ==============

  private notificationsKey(): string {
    return `cached_notifications_${this.auth.uid}`
  }

  private async loadCachedNotifications(): Promise<void> {
    if (!this.auth.uid) return
    const saved = await this.store.getJSON<NgaNotification[]>(this.notificationsKey())
    if (saved && saved.length > 0) {
      this.cachedNotifications = saved
    }
  }

  private persistCachedNotifications(): void {
    if (!this.auth.uid) return
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.notificationsKey(), this.cachedNotifications, false)
      this.store.scheduleFlush()
    })
  }

  getCachedNotifications(): NgaNotification[] {
    return this.cachedNotifications
  }

  updateCachedNotifications(data: NgaNotification[]): void {
    this.cachedNotifications = data
    this.persistCachedNotifications()
  }

  clearCachedNotifications(): void {
    this.cachedNotifications = []
    if (this.auth.uid) {
      this.writeQueue.enqueue(async (): Promise<void> => {
        await this.store.putJSON(this.notificationsKey(), [], false)
        this.store.scheduleFlush()
      })
    }
  }
}
