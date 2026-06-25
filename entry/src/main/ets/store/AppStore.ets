import { hilog } from '@kit.PerformanceAnalysisKit'
import { Context } from '@kit.AbilityKit'
import { PreferencesStore } from '../common/infra/PreferencesStore'
import { SerialQueue } from '../common/infra/SerialQueue'
import { AuthStore } from './AuthStore'
import { SettingsStore } from './SettingsStore'
import { CategoryStore } from './CategoryStore'
import { ProfileStore } from './ProfileStore'
import { NotificationStore } from './NotificationStore'
import { VoteStore } from './VoteStore'
import { HistoryStore } from './HistoryStore'
import { ToastManager } from '../common/feedback/ToastManager'

import type { AuthState, Session } from './AuthStore'
import type { SettingsState, FavBoard, BlacklistEntry } from './SettingsStore'
import type { BrowseHistoryEntry } from './HistoryStore'
import type { ToastState } from '../common/feedback/ToastManager'
import type { ProfileData } from '../model/User'
import type { ThreadResult } from '../model/ThreadResult'
import type { NgaNotification } from '../model/Notification'
import type { Category } from '../model/Forum'

const TAG = 'AppStore'
const DOMAIN = 0x0000

/**
 * AppStore — 全局状态管理 Facade
 *
 * 各领域职责已拆分到独立 Store，AppStore 只做编排和委托。
 */
class AppStoreClass {
  // ---------- Infrastructure ----------
  private store: PreferencesStore = new PreferencesStore()
  private writeQueue: SerialQueue = new SerialQueue()
  private context?: Context

  // ---------- Sub Stores ----------
  readonly authStore: AuthStore = new AuthStore()
  readonly settingsStore: SettingsStore = new SettingsStore()
  readonly categoryStore: CategoryStore = new CategoryStore()
  readonly profileStore: ProfileStore = new ProfileStore()
  readonly notificationStore: NotificationStore = new NotificationStore()
  readonly voteStore: VoteStore = new VoteStore()
  readonly historyStore: HistoryStore = new HistoryStore()
  readonly toastManager: ToastManager = new ToastManager()

  // ============== Init & Lifecycle ==============

  async init(context: Context): Promise<void> {
    try {
      this.context = context
      await this.store.init(context, 'nga_app_store')

      // 子 Store 中不依赖 uid 的先初始化（同步赋值引用）
      await this.voteStore.init(this.store, this.writeQueue)
      await this.historyStore.init(this.store, this.writeQueue)

      // 认证 + 分类（部分依赖 uid）
      await this.authStore.init(this.store, this.writeQueue)
      await this.categoryStore.init(this.store, this.writeQueue, this.authStore.state)

      // 用户数据（依赖 uid）
      if (this.authStore.state.uid) {
        await this.loadUserData()
      }
      this.settingsStore.applyCurrentTheme()

      hilog.info(DOMAIN, TAG, 'AppStore initialized')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'AppStore init failed: %{public}s', JSON.stringify(e))
    }
  }

  private async loadUserData(): Promise<void> {
    await this.settingsStore.init(this.store, this.writeQueue, this.authStore.state, this.context)
    await this.profileStore.init(this.store, this.writeQueue, this.authStore.state)
    await this.notificationStore.init(this.store, this.writeQueue, this.authStore.state)
  }

  /** 后台时刷盘 */
  async flushAll(): Promise<void> {
    await this.writeQueue.enqueue(async (): Promise<void> => {})
    await this.store.flush()
  }

  // ---------- Facade: Auth ----------

  get auth(): AuthState {
    return this.authStore.state
  }

  async setAuth(token: string, uid: string, nickName: string, avatarUrl: string): Promise<void> {
    const uidChanged = await this.authStore.setAuth(token, uid, nickName, avatarUrl)
    if (uidChanged) {
      await this.loadUserData()
      this.settingsStore.applyCurrentTheme()
    }
  }

  clearAuth(): void {
    this.authStore.clearAuth()
    this.settingsStore.reset()
    this.categoryStore.reset()
    this.profileStore.reset()
    this.notificationStore.reset()
    this.voteStore.reset()
    this.historyStore.reset()
  }

  createSession(uid: string, cid: string, nickName: string, avatarUrl: string): Promise<string> {
    return this.authStore.createSession(uid, cid, nickName, avatarUrl)
  }

  getSession(token: string): Session | null {
    return this.authStore.getSession(token)
  }

  updateSession(token: string, nickName?: string, avatarUrl?: string): Promise<void> {
    return this.authStore.updateSession(token, nickName, avatarUrl)
  }

  destroySession(token: string): Promise<void> {
    return this.authStore.destroySession(token)
  }

  // ---------- Facade: Settings ----------

  get settings(): SettingsState {
    return this.settingsStore.state
  }

  addBlacklist(entry: BlacklistEntry): void { this.settingsStore.addBlacklist(entry) }
  removeBlacklist(userId: string): void { this.settingsStore.removeBlacklist(userId) }
  removeAllBlacklist(): void { this.settingsStore.removeAllBlacklist() }
  getBlacklistIds(): Set<string> { return this.settingsStore.getBlacklistIds() }
  getBlacklistHeaderString(): string { return this.settingsStore.getBlacklistHeaderString() }

  ensureFavorites(): void { this.settingsStore.ensureFavorites() }
  addFavorite(board: FavBoard): void { this.settingsStore.addFavorite(board) }
  removeFavorite(fid: number): void { this.settingsStore.removeFavorite(fid) }

  setFontSize(size: number): void { this.settingsStore.setFontSize(size) }
  setDomainIndex(index: number): void { this.settingsStore.setDomainIndex(index) }
  setTheme(theme: string): void { this.settingsStore.setTheme(theme) }
  setAutoCheckin(enabled: boolean): void { this.settingsStore.setAutoCheckin(enabled) }
  autoCheckinIfNeeded(): void { this.settingsStore.autoCheckinIfNeeded() }
  setSmartGrip(enabled: boolean): void { this.settingsStore.setSmartGrip(enabled) }
  setShowSignature(enabled: boolean): void { this.settingsStore.setShowSignature(enabled) }

  setTtsPerson(v: number): void { this.settingsStore.setTtsPerson(v) }
  setTtsSpeed(v: number): void { this.settingsStore.setTtsSpeed(v) }
  setTtsVolume(v: number): void { this.settingsStore.setTtsVolume(v) }
  setTtsPitch(v: number): void { this.settingsStore.setTtsPitch(v) }

  setImageLoadStrategy(v: string): void { this.settingsStore.setImageLoadStrategy(v) }
  setEnableImageSizePrefetch(enabled: boolean): void { this.settingsStore.setEnableImageSizePrefetch(enabled) }
  setVideoMuted(enabled: boolean): void { this.settingsStore.setVideoMuted(enabled) }
  setThreadNavMode(v: string): void { this.settingsStore.setThreadNavMode(v) }
  setPrefetchPageCount(v: number): void { this.settingsStore.setPrefetchPageCount(v) }

  addOrUpdateNote(userId: string, nickName: string, note: string): void {
    this.settingsStore.addOrUpdateNote(userId, nickName, note)
  }
  removeNote(userId: string): void { this.settingsStore.removeNote(userId) }
  removeAllNotes(): void { this.settingsStore.removeAllNotes() }
  getNote(userId: string): string { return this.settingsStore.getNote(userId) }
  getNoteMap(): Record<string, string> { return this.settingsStore.getNoteMap() }

  addKeyword(keyword: string): void { this.settingsStore.addKeyword(keyword) }
  removeKeyword(keyword: string): void { this.settingsStore.removeKeyword(keyword) }
  toggleKeyword(keyword: string): void { this.settingsStore.toggleKeyword(keyword) }
  removeAllKeywords(): void { this.settingsStore.removeAllKeywords() }
  getEnabledKeywords(): string[] { return this.settingsStore.getEnabledKeywords() }

  // ---------- Facade: Categories ----------

  get cachedCategories(): Category[] {
    return this.categoryStore.cachedCategories
  }

  get categoriesLoaded(): boolean {
    return this.categoryStore.categoriesLoaded
  }

  get categoriesError(): string {
    return this.categoryStore.categoriesError
  }

  ensureCategories(): void { this.categoryStore.ensureCategories() }

  // ---------- Facade: Profile ----------

  getCachedProfile(uid: string): ProfileData | null { return this.profileStore.getCachedProfile(uid) }
  ensureProfile(uid: string): void { this.profileStore.ensureProfile(uid) }

  // ---------- Facade: Notifications ----------

  get unreadNotiCount(): number {
    return this.notificationStore.unreadNotiCount
  }

  refreshUnreadCount(): Promise<void> { return this.notificationStore.refreshUnreadCount() }
  getCachedNotifications(): NgaNotification[] { return this.notificationStore.getCachedNotifications() }
  updateCachedNotifications(data: NgaNotification[]): void { this.notificationStore.updateCachedNotifications(data) }
  clearCachedNotifications(): void { this.notificationStore.clearCachedNotifications() }

  // ---------- Facade: Vote ----------

  loadVoteRecord(uid: string, tid: string): Promise<Set<string>[]> {
    return this.voteStore.loadVoteRecord(uid, tid)
  }
  saveVoteRecord(uid: string, tid: string, upPids: Set<string>, downPids: Set<string>): Promise<void> {
    return this.voteStore.saveVoteRecord(uid, tid, upPids, downPids)
  }
  removeVoteRecord(uid: string, tid: string): Promise<void> { return this.voteStore.removeVoteRecord(uid, tid) }
  clearVoteRecords(uid: string): Promise<void> { return this.voteStore.clearVoteRecords(uid) }

  // ---------- Facade: Browse History ----------

  getBrowseHistory(uid: string): Promise<BrowseHistoryEntry[]> { return this.historyStore.getBrowseHistory(uid) }
  addBrowseHistory(uid: string, entry: BrowseHistoryEntry): Promise<void> {
    return this.historyStore.addBrowseHistory(uid, entry)
  }
  addBrowseHistoryFromThread(uid: string, result: ThreadResult, tid: string): Promise<void> {
    return this.historyStore.addFromThreadResult(uid, result, tid)
  }
  removeBrowseHistory(uid: string, tid: string): Promise<void> { return this.historyStore.removeBrowseHistory(uid, tid) }
  clearBrowseHistory(uid: string): Promise<void> { return this.historyStore.clearBrowseHistory(uid) }

  // ---------- Facade: Toast ----------

  get toast(): ToastState {
    return this.toastManager.state
  }

  showToast(msg: string): void { this.toastManager.show(msg) }
}

export const appStore = new AppStoreClass()
