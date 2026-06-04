import { hilog } from '@kit.PerformanceAnalysisKit'
import { ConfigurationConstant, Context } from '@kit.AbilityKit'
import { fetchForumFavorites, getForumCategories, getUserProfile, getNotifications } from '../service/NgaApi'
import type { Category } from '../model/Forum'
import type { ProfileData } from '../model/User'
import { checkin } from '../service/NgaApi'
import { PreferencesStore } from './PreferencesStore'
import { SerialQueue } from './SerialQueue'
import { LruCache } from '../common/LruCache'
import { updateStatusBarStyle } from '../common/StatusBarManager'
import type { UserNoteEntry } from '../model/NoteInfo'
import type { NgaNotification } from '../model/Notification'
import { FilterKeyword } from '../model/FilterKeyword'
import { FilterListManager } from './FilterListManager'
import { ImageLoadStrategy } from '../common/Constants'

const TAG = 'AppStore'
const DOMAIN = 0x0000

@Observed
export class AuthState {
  token: string = ''
  uid: string = ''
  nickName: string = ''
  avatarUrl: string = ''
  isAuthenticated: boolean = false
  initialized: boolean = false
}

export interface BlacklistEntry {
  userId: string
  nickName: string
}

export class FavBoard {
  fid: number = 0
  stid: number = 0
  name: string = ''
}

export class SettingsState {
  blacklist: BlacklistEntry[] = []
  filterKeywords: FilterKeyword[] = []
  favorites: FavBoard[] = []
  fontSize: number = 15
  domainIndex: number = 0
  theme: string = 'light'
  autoCheckin: boolean = false
  lastCheckinDate: string = ''
  notes: UserNoteEntry[] = []
  holdingHand: number = 2
  smartGrip: boolean = true
  showSignature: boolean = true
  ttsPerson: number = 13
  ttsSpeed: number = 1.0
  ttsVolume: number = 1.0
  ttsPitch: number = 1.0
  imageLoadStrategy: string = ImageLoadStrategy.ALWAYS
  enableImageSizePrefetch: boolean = true
}

export class ToastState {
  message: string = ''
  visible: boolean = false
}

class PersistedAuth {
  token: string = ''
  uid: string = ''
  nickName: string = ''
  avatarUrl: string = ''
}

// ============== Session ==============

export interface Session {
  uid: string
  cid: string
  nickName: string
  avatarUrl: string
  createdAt: number
}

const SESSION_MAX_AGE: number = 7 * 24 * 3600 * 1000
const SESSION_KEY: string = 'sessions'

// ============== Vote Record ==============

class VoteRecord {
  upPids: string[] = []
  downPids: string[] = []
  ts: number = 0
}

const VOTE_MAX_ENTRIES: number = 200

// ============== Browse History ==============

export class BrowseHistoryEntry {
  tid: string = ''
  subject: string = ''
  author: string = ''
  authorid: string = ''
  replies: number = 0
  postDate: number = 0
  board: string = ''
  ts: number = 0
}

const HISTORY_MAX_COUNT: number = 500

// ============== AppStore ==============

class AppStoreClass {
  private store: PreferencesStore = new PreferencesStore()
  private writeQueue: SerialQueue = new SerialQueue()

  auth: AuthState = new AuthState()
  settings: SettingsState = new SettingsState()
  toast: ToastState = new ToastState()
  private toastTimer: number = -1
  private context?: Context

  cachedCategories: Category[] = []
  private categoriesVersion: number = 0
  private categoriesRefreshing: boolean = false

  private blacklistManager: FilterListManager<BlacklistEntry> = new FilterListManager<BlacklistEntry>()

  private notesManager: FilterListManager<UserNoteEntry> = new FilterListManager<UserNoteEntry>()

  private filterKeywordsManager: FilterListManager<FilterKeyword> = new FilterListManager<FilterKeyword>()

  private profileCache: LruCache<ProfileData> = new LruCache<ProfileData>(200, 5 * 60 * 1000)
  private profileVersion: number = 0
  private refreshingUids: Set<string> = new Set()

  unreadNotiCount: number = 0

  private cachedNotifications: NgaNotification[] = []
  private lastNotiQueryTime: number = 0
  private static readonly NOTI_QUERY_DELAY: number = 30 * 1000

  // Session state
  private sessions: Map<string, Session> = new Map()
  private sessionsDirty: boolean = false

  // Vote state
  private voteCache: Record<string, VoteRecord> = {}
  private voteLoadedUid: string = ''

  // Browse history state
  private historyItems: BrowseHistoryEntry[] = []
  private historyLoadedUid: string = ''
  private historyVersion: number = 0

  private static readonly REFRESH_DELAY: number = 10000

  // ============== Init ==============

  async init(context: Context): Promise<void> {
    try {
      this.context = context
      await this.store.init(context, 'nga_app_store')
      await this.loadSessions()
      await this.migrateAuthIfNeeded()
      await this.loadAuth()
      await this.loadCachedCategories()
      if (this.auth.uid) {
        await this.loadUserSettings()
        await this.loadCachedProfiles()
        await this.loadCachedNotifications()
      }
      this.applyCurrentTheme()
      hilog.info(DOMAIN, TAG, 'AppStore initialized')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'AppStore init failed: %{public}s', JSON.stringify(e))
    }
  }

  // ============== Auth ==============

  async setAuth(token: string, uid: string, nickName: string, avatarUrl: string): Promise<void> {
    const uidChanged = this.auth.uid !== uid
    this.auth.token = token
    this.auth.uid = uid
    this.auth.nickName = nickName
    this.auth.avatarUrl = avatarUrl
    this.auth.isAuthenticated = true
    this.auth.initialized = true
    this.persistAuth()
    if (uidChanged) {
      this.resetUserState()
      await this.loadUserSettings()
      await this.loadCachedProfiles()
      await this.loadCachedNotifications()
      this.applyCurrentTheme()
    }
  }

  clearAuth(): void {
    this.auth.token = ''
    this.auth.uid = ''
    this.auth.nickName = ''
    this.auth.avatarUrl = ''
    this.auth.isAuthenticated = false
    this.auth.initialized = true
    this.persistAuth()
    this.resetUserState()
  }

  private persistAuth(): void {
    const data = new PersistedAuth()
    data.token = this.auth.token
    data.uid = this.auth.uid
    data.nickName = this.auth.nickName
    data.avatarUrl = this.auth.avatarUrl
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON('auth', data, false)
      this.store.scheduleFlush()
    })
  }

  private async loadAuth(): Promise<void> {
    const saved = await this.store.getJSON<PersistedAuth>('auth')
    if (saved) {
      this.auth.token = saved.token
      this.auth.uid = saved.uid
      this.auth.nickName = saved.nickName
      this.auth.avatarUrl = saved.avatarUrl
      this.auth.isAuthenticated = this.auth.token !== ''
    }
    this.auth.initialized = true
  }

  private async migrateAuthIfNeeded(): Promise<void> {
    const oldToken = await this.store.getString('auth_token')
    if (!oldToken) return
    const uid = await this.store.getString('auth_uid')
    const nickName = await this.store.getString('auth_nickName')
    const avatarUrl = await this.store.getString('auth_avatarUrl')
    const data = new PersistedAuth()
    data.token = oldToken
    data.uid = uid
    data.nickName = nickName
    data.avatarUrl = avatarUrl
    await this.store.putJSON('auth', data, false)
    await this.store.putString('auth_token', '', false)
    await this.store.putString('auth_uid', '', false)
    await this.store.putString('auth_nickName', '', false)
    await this.store.putString('auth_avatarUrl', '', false)
    await this.store.putString('auth_isAuth', '', false)
    await this.store.flush()
    hilog.info(DOMAIN, TAG, 'Auth migrated from old format')
  }

  // ============== Settings ==============

  addBlacklist(entry: BlacklistEntry): void {
    this.settings.blacklist = this.blacklistManager.add(entry)
    this.persistSettings()
  }

  removeBlacklist(userId: string): void {
    this.settings.blacklist = this.blacklistManager.remove((u: BlacklistEntry) => u.userId === userId)
    this.persistSettings()
  }

  removeAllBlacklist(): void {
    this.settings.blacklist = this.blacklistManager.clear()
    this.persistSettings()
  }

  getBlacklistIds(): Set<string> {
    const ids = new Set<string>()
    for (let i = 0; i < this.settings.blacklist.length; i++) {
      ids.add(this.settings.blacklist[i].userId)
    }
    return ids
  }

  private favoritesLoaded: boolean = false

  ensureFavorites(): void {
    if (this.favoritesLoaded || !this.auth.isAuthenticated) return
    const hasCache = this.settings.favorites.length > 0
    if (hasCache) {
      this.favoritesLoaded = true
    }
    setTimeout(async () => {
      await this.doRefreshFavorites()
    }, hasCache ? AppStoreClass.REFRESH_DELAY : 0)
  }

  private async doRefreshFavorites(): Promise<void> {
    if (!this.auth.isAuthenticated) return
    try {
      const result = await fetchForumFavorites(this.auth.token)
      if (result.ok && result.data.length > 0) {
        const favs: FavBoard[] = []
        for (let i = 0; i < result.data.length; i++) {
          const item = result.data[i]
          const fb = new FavBoard()
          fb.fid = item.fid
          fb.stid = item.stid
          fb.name = item.name
          favs.push(fb)
        }
        this.settings.favorites = favs
        this.persistSettings()
        AppStorage.setOrCreate('favVersion', (AppStorage.get<number>('favVersion') ?? 0) + 1)
      }
      this.favoritesLoaded = true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchFavorites failed')
    }
  }

  addFavorite(board: FavBoard): void {
    this.settings.favorites = [...this.settings.favorites, board]
    this.persistSettings()
    AppStorage.setOrCreate('favVersion', (AppStorage.get<number>('favVersion') ?? 0) + 1)
  }

  removeFavorite(fid: number): void {
    this.settings.favorites = this.settings.favorites.filter(f => f.fid !== fid)
    this.persistSettings()
    AppStorage.setOrCreate('favVersion', (AppStorage.get<number>('favVersion') ?? 0) + 1)
  }

  setFontSize(size: number): void {
    this.settings.fontSize = size
    this.persistSettings()
  }

  setDomainIndex(index: number): void {
    this.settings.domainIndex = index
    this.persistSettings()
  }

  setTheme(theme: string): void {
    this.settings.theme = theme
    this.applyCurrentTheme()
    this.persistSettings()
  }

  setAutoCheckin(enabled: boolean): void {
    this.settings.autoCheckin = enabled
    this.persistSettings()
  }

  setSmartGrip(enabled: boolean): void {
    this.settings.smartGrip = enabled
    this.persistSettings()
  }

  setShowSignature(enabled: boolean): void {
    this.settings.showSignature = enabled
    AppStorage.setOrCreate('showSignature', enabled)
    this.persistSettings()
  }

  setTtsPerson(v: number): void {
    this.settings.ttsPerson = v
    this.persistSettings()
  }

  setTtsSpeed(v: number): void {
    this.settings.ttsSpeed = v
    this.persistSettings()
  }

  setTtsVolume(v: number): void {
    this.settings.ttsVolume = v
    this.persistSettings()
  }

  setTtsPitch(v: number): void {
    this.settings.ttsPitch = v
    this.persistSettings()
  }

  setImageLoadStrategy(v: string): void {
    this.settings.imageLoadStrategy = v
    AppStorage.setOrCreate('imageLoadStrategy', v)
    let version: number = AppStorage.get<number>('networkChangeVersion') ?? 0
    AppStorage.setOrCreate('networkChangeVersion', version + 1)
    this.persistSettings()
  }

  setEnableImageSizePrefetch(enabled: boolean): void {
    this.settings.enableImageSizePrefetch = enabled
    AppStorage.setOrCreate('enableImageSizePrefetch', enabled)
    this.persistSettings()
  }

  async autoCheckinIfNeeded(): Promise<void> {
    if (!this.auth.isAuthenticated || !this.settings.autoCheckin) {
      return
    }
    const d: Date = new Date()
    const today: string = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    if (this.settings.lastCheckinDate === today) {
      return
    }
    try {
      const result = await checkin(this.auth.token)
      if (result.ok) {
        this.settings.lastCheckinDate = today
        this.persistSettings()
        this.showToast('自动签到成功')
      }
    } catch (e) {
      // 自动签到失败静默
    }
  }

  private applyCurrentTheme(): void {
    let theme: string = this.settings.theme
    if (theme === 'original' || theme === 'white') {
      theme = 'light'
    }
    let mode: number
    let effectiveTheme: string
    if (theme === 'system') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      effectiveTheme = AppStorage.get<string>('effectiveColorMode') ?? 'light'
    } else if (theme === 'dark') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      effectiveTheme = 'dark'
    } else {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      effectiveTheme = 'light'
    }
    try {
      this.context?.getApplicationContext().setColorMode(mode)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(err))
    }
    AppStorage.setOrCreate('themeName', theme)
    AppStorage.setOrCreate('effectiveColorMode', effectiveTheme)

    try {
      updateStatusBarStyle(effectiveTheme === 'dark')
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'updateStatusBarStyle failed: %{public}s', JSON.stringify(err))
    }
  }

  persistSettings(): void {
    if (!this.auth.uid) return
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.settingsKey(), this.settings, false)
      this.store.scheduleFlush()
    })
  }

  private settingsKey(): string {
    return `settings_${this.auth.uid}`
  }

  private async loadUserSettings(): Promise<void> {
    if (!this.auth.uid) return
    const saved = await this.store.getJSON<SettingsState>(this.settingsKey())
    if (saved) {
      if (saved.favorites) this.settings.favorites = saved.favorites
      if (saved.blacklist) {
        this.settings.blacklist = saved.blacklist
        this.blacklistManager.init(saved.blacklist)
      }
      if (saved.notes) {
        this.settings.notes = saved.notes
        this.notesManager.init(saved.notes)
      }
      if (saved.filterKeywords) {
        this.settings.filterKeywords = saved.filterKeywords
        this.filterKeywordsManager.init(saved.filterKeywords)
      }
      if (saved.fontSize) this.settings.fontSize = saved.fontSize
      if (saved.domainIndex) this.settings.domainIndex = saved.domainIndex
      if (saved.theme) this.settings.theme = saved.theme
      if (saved.autoCheckin !== undefined) this.settings.autoCheckin = saved.autoCheckin
      if (saved.lastCheckinDate) this.settings.lastCheckinDate = saved.lastCheckinDate
      if (saved.holdingHand !== undefined) this.settings.holdingHand = saved.holdingHand
      if (saved.smartGrip !== undefined) this.settings.smartGrip = saved.smartGrip
      if (saved.showSignature !== undefined) this.settings.showSignature = saved.showSignature
      if (saved.ttsPerson !== undefined) this.settings.ttsPerson = saved.ttsPerson
      if (saved.ttsSpeed !== undefined) this.settings.ttsSpeed = saved.ttsSpeed
      if (saved.ttsVolume !== undefined) this.settings.ttsVolume = saved.ttsVolume
      if (saved.ttsPitch !== undefined) this.settings.ttsPitch = saved.ttsPitch
      if (saved.imageLoadStrategy !== undefined) this.settings.imageLoadStrategy = saved.imageLoadStrategy
      if (saved.enableImageSizePrefetch !== undefined) this.settings.enableImageSizePrefetch = saved.enableImageSizePrefetch
    }
    AppStorage.setOrCreate('showSignature', this.settings.showSignature)
    AppStorage.setOrCreate('imageLoadStrategy', this.settings.imageLoadStrategy)
    AppStorage.setOrCreate('enableImageSizePrefetch', this.settings.enableImageSizePrefetch)
  }

  private resetUserState(): void {
    this.settings = new SettingsState()
    this.blacklistManager = new FilterListManager<BlacklistEntry>()
    this.notesManager = new FilterListManager<UserNoteEntry>()
    this.filterKeywordsManager = new FilterListManager<FilterKeyword>()
    this.profileCache.clear()
    this.cachedNotifications = []
    this.favoritesLoaded = false
    this.refreshingUids = new Set()
    this.voteCache = {}
    this.voteLoadedUid = ''
    this.historyItems = []
    this.historyLoadedUid = ''
    this.historyVersion = 0
  }

  // ============== Categories Cache ==============

  private async loadCachedCategories(): Promise<void> {
    const saved = await this.store.getJSON<Category[]>('cached_categories')
    if (saved && saved.length > 0) {
      this.cachedCategories = saved
      this.categoriesVersion++
      AppStorage.setOrCreate('catVersion', this.categoriesVersion)
      hilog.info(DOMAIN, TAG, 'Loaded cached categories: %{public}d', saved.length)
    }
  }

  private persistCategories(): void {
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON('cached_categories', this.cachedCategories, false)
      this.store.scheduleFlush()
    })
  }

  ensureCategories(): void {
    if (this.categoriesRefreshing) return
    this.categoriesRefreshing = true
    const hasCache = this.cachedCategories.length > 0
    setTimeout(async () => {
      await this.doRefreshCategories()
      this.categoriesRefreshing = false
    }, hasCache ? AppStoreClass.REFRESH_DELAY : 0)
  }

  private async doRefreshCategories(): Promise<void> {
    if (!this.auth.isAuthenticated) return
    try {
      const result = await getForumCategories(this.auth.token)
      if (result.ok && result.data.length > 0) {
        const newJson = JSON.stringify(result.data)
        const oldJson = JSON.stringify(this.cachedCategories)
        if (newJson !== oldJson) {
          this.cachedCategories = result.data
          this.categoriesVersion++
          AppStorage.setOrCreate('catVersion', this.categoriesVersion)
          this.persistCategories()
          hilog.info(DOMAIN, TAG, 'Categories updated from network')
        } else {
          hilog.info(DOMAIN, TAG, 'Categories unchanged')
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'refreshCategories failed')
    }
  }

  // ============== Profile Cache ==============

  private profilesKey(): string {
    return `cached_profiles_${this.auth.uid}`
  }

  private async loadCachedProfiles(): Promise<void> {
    if (!this.auth.uid) return
    const saved = await this.store.getJSON<Record<string, ProfileData>>(this.profilesKey())
    if (saved) {
      const keys = Object.keys(saved)
      for (let i = 0; i < keys.length; i++) {
        const val = saved[keys[i]]
        if (val) {
          this.profileCache.set(keys[i], val)
        }
      }
      hilog.info(DOMAIN, TAG, 'Loaded cached profiles: %{public}d', keys.length)
    }
  }

  private persistProfiles(): void {
    if (!this.auth.uid) return
    const snapshot: Record<string, ProfileData> = {}
    const keys: string[] = this.profileCache.keys()
    for (let i = 0; i < keys.length; i++) {
      const val = this.profileCache.get(keys[i])
      if (val) {
        snapshot[keys[i]] = val
      }
    }
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.profilesKey(), snapshot, false)
      this.store.scheduleFlush()
    })
  }

  getCachedProfile(uid: string): ProfileData | null {
    const result = this.profileCache.getWithStale(uid)
    if (result.value) {
      if (result.stale) {
        this.ensureProfile(uid)
      }
      return result.value
    }
    return null
  }

  ensureProfile(uid: string): void {
    if (this.refreshingUids.has(uid)) return
    this.refreshingUids.add(uid)
    const hasCache = this.profileCache.isFresh(uid)
    setTimeout(async () => {
      await this.doRefreshProfile(uid)
      this.refreshingUids.delete(uid)
    }, hasCache ? AppStoreClass.REFRESH_DELAY : 0)
  }

  private async doRefreshProfile(uid: string): Promise<ProfileData | null> {
    if (!this.auth.isAuthenticated) return null
    try {
      const result = await getUserProfile(this.auth.token, uid)
      if (result.ok && result.data) {
        const newJson = JSON.stringify(result.data)
        const cachedResult = this.profileCache.getWithStale(uid)
        const oldJson = cachedResult.value ? JSON.stringify(cachedResult.value) : ''
        this.profileCache.set(uid, result.data)
        if (newJson !== oldJson) {
          this.profileVersion++
          AppStorage.setOrCreate('profileVersion', this.profileVersion)
          this.persistProfiles()
        }
        return result.data
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'refreshProfile failed for uid=%{public}s', uid)
    }
    return null
  }

  // ============== Notifications ==============

  private notificationsKey(): string {
    return `cached_notifications_${this.auth.uid}`
  }

  async refreshUnreadCount(): Promise<void> {
    if (!this.auth.isAuthenticated) return
    const now: number = Date.now()
    if (now - this.lastNotiQueryTime < AppStoreClass.NOTI_QUERY_DELAY) return
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
        AppStorage.setOrCreate('unreadNotiCount', this.unreadNotiCount)
        this.cachedNotifications = result.data
        this.persistCachedNotifications()
      }
    } catch (e) {}
  }

  async loadCachedNotifications(): Promise<void> {
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

  // ============== Toast ==============

  showToast(msg: string): void {
    clearTimeout(this.toastTimer)
    this.toast.message = msg
    this.toast.visible = true
    this.toastTimer = setTimeout(() => {
      this.toast.visible = false
      this.toast.message = ''
    }, 2500)
  }

  // ============== Blacklist helper ==============

  getBlacklistHeaderString(): string {
    return this.settings.blacklist.map(u => u.userId).join(',')
  }

  // ============== User Notes ==============

  addOrUpdateNote(userId: string, nickName: string, note: string): void {
    const existing: UserNoteEntry | undefined = this.settings.notes.find((n: UserNoteEntry) => n.userId === userId)
    if (existing) {
      existing.note = note
      existing.nickName = nickName
    } else {
      this.settings.notes = this.notesManager.add({ userId, nickName, note })
    }
    this.persistSettings()
  }

  removeNote(userId: string): void {
    this.settings.notes = this.notesManager.remove((n: UserNoteEntry) => n.userId === userId)
    this.persistSettings()
  }

  removeAllNotes(): void {
    this.settings.notes = this.notesManager.clear()
    this.persistSettings()
  }

  getNote(userId: string): string {
    const entry: UserNoteEntry | undefined = this.settings.notes.find((n: UserNoteEntry) => n.userId === userId)
    return entry?.note ?? ''
  }

  getNoteMap(): Record<string, string> {
    const map: Record<string, string> = {}
    for (let i = 0; i < this.settings.notes.length; i++) {
      map[this.settings.notes[i].userId] = this.settings.notes[i].note
    }
    return map
  }

  // ============== Filter Keywords ==============

  addKeyword(keyword: string): void {
    const item = new FilterKeyword()
    item.keyword = keyword
    item.enabled = true
    this.settings.filterKeywords = this.filterKeywordsManager.add(item)
    this.persistSettings()
  }

  removeKeyword(keyword: string): void {
    this.settings.filterKeywords = this.filterKeywordsManager.remove((k: FilterKeyword) => k.keyword === keyword)
    this.persistSettings()
  }

  toggleKeyword(keyword: string): void {
    const list = this.filterKeywordsManager.getList()
    for (let i = 0; i < list.length; i++) {
      if (list[i].keyword === keyword) {
        list[i].enabled = !list[i].enabled
        this.settings.filterKeywords = [...list]
        this.persistSettings()
        return
      }
    }
  }

  removeAllKeywords(): void {
    this.filterKeywordsManager.clear()
    this.settings.filterKeywords = this.filterKeywordsManager.getList()
    this.persistSettings()
  }

  getEnabledKeywords(): string[] {
    const result: string[] = []
    const list = this.settings.filterKeywords
    for (let i = 0; i < list.length; i++) {
      if (list[i].enabled) {
        result.push(list[i].keyword)
      }
    }
    return result
  }

  // ============== Session (原 SessionStore) ==============

  private async loadSessions(): Promise<void> {
    const saved = await this.store.getJSON<Array<Array<Object>>>(SESSION_KEY)
    if (!saved) return
    for (let i = 0; i < saved.length; i++) {
      const entry = saved[i]
      const token = String(entry[0])
      const sessionObj = entry[1] as Record<string, Object>
      const session: Session = {
        uid: String(sessionObj['uid'] ?? ''),
        cid: String(sessionObj['cid'] ?? ''),
        nickName: String(sessionObj['nickName'] ?? ''),
        avatarUrl: String(sessionObj['avatarUrl'] ?? ''),
        createdAt: Number(sessionObj['createdAt'] ?? 0),
      }
      this.sessions.set(token, session)
    }
    this.cleanupSessions()
    hilog.info(DOMAIN, TAG, 'Sessions loaded: %{public}d', this.sessions.size)
  }

  private persistSessions(immediate: boolean = false): void {
    if (!this.sessionsDirty) return
    this.sessionsDirty = false
    const entries: Array<Array<Object>> = []
    const keys = Array.from(this.sessions.keys())
    for (const key of keys) {
      const session = this.sessions.get(key)
      if (session) {
        entries.push([key, session])
      }
    }
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(SESSION_KEY, entries, immediate)
    })
  }

  async createSession(uid: string, cid: string, nickName: string, avatarUrl: string): Promise<string> {
    const token = this.generateToken()
    this.sessions.set(token, { uid, cid, nickName, avatarUrl, createdAt: Date.now() })
    this.sessionsDirty = true
    this.persistSessions(true) // 登录会话立即刷盘，防止丢失
    return token
  }

  getSession(token: string): Session | null {
    return this.sessions.get(token) ?? null
  }

  async updateSession(token: string, nickName?: string, avatarUrl?: string): Promise<void> {
    const session = this.sessions.get(token)
    if (!session) return
    if (nickName !== undefined) session.nickName = nickName
    if (avatarUrl !== undefined) session.avatarUrl = avatarUrl
    this.sessionsDirty = true
    this.persistSessions()
  }

  async destroySession(token: string): Promise<void> {
    if (this.sessions.delete(token)) {
      this.sessionsDirty = true
      this.persistSessions(true) // 销毁会话立即刷盘
    }
  }

  cleanupSessions(): void {
    const now = Date.now()
    let changed = false
    const keys = Array.from(this.sessions.keys())
    for (const token of keys) {
      const session = this.sessions.get(token)!
      if (now - session.createdAt > SESSION_MAX_AGE) {
        this.sessions.delete(token)
        changed = true
      }
    }
    if (changed) {
      this.sessionsDirty = true
    }
  }

  private generateToken(): string {
    const chars = '0123456789abcdef'
    let result = ''
    for (let i = 0; i < 64; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return result
  }

  // ============== Vote Record (原 VoteRecordStore) ==============

  private voteKey(uid: string): string {
    return `votes_${uid}`
  }

  async loadVoteRecord(uid: string, tid: string): Promise<Set<string>[]> {
    if (uid.length === 0) {
      return [new Set<string>(), new Set<string>()]
    }
    if (this.voteLoadedUid !== uid) {
      const saved = await this.store.getJSON<Record<string, VoteRecord>>(this.voteKey(uid))
      this.voteCache = saved ?? {}
      this.voteLoadedUid = uid
    }
    const upSet = new Set<string>()
    const downSet = new Set<string>()
    const record = this.voteCache[tid]
    if (record) {
      for (let i = 0; i < record.upPids.length; i++) {
        upSet.add(record.upPids[i])
      }
      for (let i = 0; i < record.downPids.length; i++) {
        downSet.add(record.downPids[i])
      }
    }
    return [upSet, downSet]
  }

  async saveVoteRecord(uid: string, tid: string, upPids: Set<string>, downPids: Set<string>): Promise<void> {
    if (uid.length === 0 || tid.length === 0) return
    if (this.voteLoadedUid !== uid) {
      const saved = await this.store.getJSON<Record<string, VoteRecord>>(this.voteKey(uid))
      this.voteCache = saved ?? {}
      this.voteLoadedUid = uid
    }
    const record = new VoteRecord()
    const upArr: string[] = []
    upPids.forEach((pid: string) => { upArr.push(pid) })
    const downArr: string[] = []
    downPids.forEach((pid: string) => { downArr.push(pid) })
    record.upPids = upArr
    record.downPids = downArr
    record.ts = Date.now()
    this.voteCache[tid] = record
    this.evictVotesIfNeeded()
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.voteKey(uid), this.voteCache, false)
      this.store.scheduleFlush()
    })
  }

  async removeVoteRecord(uid: string, tid: string): Promise<void> {
    if (uid.length === 0) return
    if (this.voteLoadedUid !== uid) {
      const saved = await this.store.getJSON<Record<string, VoteRecord>>(this.voteKey(uid))
      this.voteCache = saved ?? {}
      this.voteLoadedUid = uid
    }
    const newCache: Record<string, VoteRecord> = {}
    const cacheKeys = Object.keys(this.voteCache)
    for (let i = 0; i < cacheKeys.length; i++) {
      if (cacheKeys[i] !== tid) {
        newCache[cacheKeys[i]] = this.voteCache[cacheKeys[i]]
      }
    }
    this.voteCache = newCache
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.voteKey(uid), this.voteCache, false)
      this.store.scheduleFlush()
    })
  }

  async clearVoteRecords(uid: string): Promise<void> {
    this.voteCache = {}
    this.voteLoadedUid = uid
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.voteKey(uid), this.voteCache, false)
      this.store.scheduleFlush()
    })
  }

  private evictVotesIfNeeded(): void {
    const keys = Object.keys(this.voteCache)
    if (keys.length <= VOTE_MAX_ENTRIES) return
    const entries: string[][] = []
    for (let i = 0; i < keys.length; i++) {
      const record = this.voteCache[keys[i]]
      if (record) {
        entries.push([keys[i], String(record.ts)])
      }
    }
    entries.sort((a: string[], b: string[]): number => {
      return Number(a[1]) - Number(b[1])
    })
    const removeCount = entries.length - VOTE_MAX_ENTRIES
    const evictSet = new Set<string>()
    for (let i = 0; i < removeCount; i++) {
      evictSet.add(entries[i][0])
    }
    const newCache: Record<string, VoteRecord> = {}
    for (let i = 0; i < keys.length; i++) {
      if (!evictSet.has(keys[i])) {
        newCache[keys[i]] = this.voteCache[keys[i]]
      }
    }
    this.voteCache = newCache
  }

  // ============== Browse History (原 BrowseHistoryStore) ==============

  private historyKey(uid: string): string {
    return `history_${uid}`
  }

  async getBrowseHistory(uid: string): Promise<BrowseHistoryEntry[]> {
    if (this.historyLoadedUid !== uid) {
      const saved = await this.store.getJSON<BrowseHistoryEntry[]>(this.historyKey(uid))
      this.historyItems = saved ?? []
      this.historyLoadedUid = uid
    }
    const result: BrowseHistoryEntry[] = []
    for (let i = 0; i < this.historyItems.length; i++) {
      result.push(this.historyItems[i])
    }
    return result
  }

  async addBrowseHistory(uid: string, entry: BrowseHistoryEntry): Promise<void> {
    if (uid.length === 0) return
    if (this.historyLoadedUid !== uid) {
      await this.getBrowseHistory(uid)
    }
    const filtered: BrowseHistoryEntry[] = []
    for (let i = 0; i < this.historyItems.length; i++) {
      if (this.historyItems[i].tid !== entry.tid) {
        filtered.push(this.historyItems[i])
      }
    }
    entry.ts = Date.now()
    const newList: BrowseHistoryEntry[] = [entry, ...filtered]
    if (newList.length > HISTORY_MAX_COUNT) {
      this.historyItems = newList.slice(0, HISTORY_MAX_COUNT)
    } else {
      this.historyItems = newList
    }
    this.persistBrowseHistory(uid)
  }

  async removeBrowseHistory(uid: string, tid: string): Promise<void> {
    if (this.historyLoadedUid !== uid) {
      await this.getBrowseHistory(uid)
    }
    const filtered: BrowseHistoryEntry[] = []
    for (let i = 0; i < this.historyItems.length; i++) {
      if (this.historyItems[i].tid !== tid) {
        filtered.push(this.historyItems[i])
      }
    }
    this.historyItems = filtered
    this.persistBrowseHistory(uid)
  }

  async clearBrowseHistory(uid: string): Promise<void> {
    this.historyItems = []
    this.persistBrowseHistory(uid)
  }

  private persistBrowseHistory(uid: string): void {
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.historyKey(uid), this.historyItems, false)
      this.historyVersion++
      AppStorage.setOrCreate('browseHistoryVersion', this.historyVersion)
      this.store.scheduleFlush()
    })
  }

  // ============== Flush All (for onBackground) ==============

  async flushAll(): Promise<void> {
    // 先排空写队列，确保所有挂起的 put 操作完成，再刷盘
    await this.writeQueue.enqueue(async (): Promise<void> => {})
    await this.store.flush()
  }
}

export const appStore = new AppStoreClass()
