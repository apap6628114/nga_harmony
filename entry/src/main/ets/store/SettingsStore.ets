import { ConfigurationConstant, Context } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { fetchForumFavorites, checkin } from '../service/NgaApi'
import { updateStatusBarStyle } from '../common/StatusBarManager'
import { FilterListManager } from './FilterListManager'
import { PreferencesStore } from './PreferencesStore'
import { SerialQueue } from './SerialQueue'
import { ImageLoadStrategy, ThreadNavMode } from '../common/Constants'
import { FilterKeyword } from '../model/FilterKeyword'
import type { UserNoteEntry } from '../model/NoteInfo'
import type { AuthState } from './AuthStore'

const TAG = 'SettingsStore'
const DOMAIN = 0x0000

/** 收藏版块 */
export class FavBoard {
  fid: number = 0
  stid: number = 0
  name: string = ''
}

/** 黑名单条目 */
export interface BlacklistEntry {
  userId: string
  nickName: string
}

/** 用户设置状态 */
@Observed
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
  threadNavMode: string = ThreadNavMode.SEAMLESS
  /** 预加载页数（0=关闭，1~5=向前预加载 N 页） */
  prefetchPageCount: number = 3
  /** 视频默认是否静音（全局开关，false=有声） */
  videoMuted: boolean = false
}

/**
 * 用户设置管理（黑名单、收藏、主题、TTS、图片策略、关键词过滤、便签等）
 */
export class SettingsStore {
  state: SettingsState = new SettingsState()
  private store!: PreferencesStore
  private writeQueue!: SerialQueue
  private auth!: AuthState
  private context?: Context
  private static readonly REFRESH_DELAY: number = 10000
  private favoritesLoaded: boolean = false
  private blacklistManager: FilterListManager<BlacklistEntry> = new FilterListManager<BlacklistEntry>()
  private notesManager: FilterListManager<UserNoteEntry> = new FilterListManager<UserNoteEntry>()
  private filterKeywordsManager: FilterListManager<FilterKeyword> = new FilterListManager<FilterKeyword>()

  async init(store: PreferencesStore, queue: SerialQueue, auth: AuthState, ctx?: Context): Promise<void> {
    this.store = store
    this.writeQueue = queue
    this.auth = auth
    this.context = ctx
    if (auth.uid) {
      await this.loadUserSettings()
    }
  }

  /** 重置为用户默认设置（切换/登出时调用） */
  reset(): void {
    this.state = new SettingsState()
    this.blacklistManager = new FilterListManager<BlacklistEntry>()
    this.notesManager = new FilterListManager<UserNoteEntry>()
    this.filterKeywordsManager = new FilterListManager<FilterKeyword>()
    this.favoritesLoaded = false
  }

  // ============== Persist ==============

  private settingsKey(): string {
    return `settings_${this.auth.uid}`
  }

  persistSettings(): void {
    if (!this.auth.uid) return
    this.writeQueue.enqueue(async (): Promise<void> => {
      await this.store.putJSON(this.settingsKey(), this.state, false)
      this.store.scheduleFlush()
    })
  }

  private async loadUserSettings(): Promise<void> {
    if (!this.auth.uid) return
    const saved = await this.store.getJSON<SettingsState>(this.settingsKey())
    if (saved) {
      if (saved.favorites) this.state.favorites = saved.favorites
      if (saved.blacklist) {
        this.state.blacklist = saved.blacklist
        this.blacklistManager.init(saved.blacklist)
      }
      if (saved.notes) {
        this.state.notes = saved.notes
        this.notesManager.init(saved.notes)
      }
      if (saved.filterKeywords) {
        this.state.filterKeywords = saved.filterKeywords
        this.filterKeywordsManager.init(saved.filterKeywords)
      }
      if (saved.fontSize) this.state.fontSize = saved.fontSize
      if (saved.domainIndex) this.state.domainIndex = saved.domainIndex
      if (saved.theme) this.state.theme = saved.theme
      if (saved.autoCheckin !== undefined) this.state.autoCheckin = saved.autoCheckin
      if (saved.lastCheckinDate) this.state.lastCheckinDate = saved.lastCheckinDate
      if (saved.holdingHand !== undefined) this.state.holdingHand = saved.holdingHand
      if (saved.smartGrip !== undefined) this.state.smartGrip = saved.smartGrip
      if (saved.showSignature !== undefined) this.state.showSignature = saved.showSignature
      if (saved.ttsPerson !== undefined) this.state.ttsPerson = saved.ttsPerson
      if (saved.ttsSpeed !== undefined) this.state.ttsSpeed = saved.ttsSpeed
      if (saved.ttsVolume !== undefined) this.state.ttsVolume = saved.ttsVolume
      if (saved.ttsPitch !== undefined) this.state.ttsPitch = saved.ttsPitch
      if (saved.imageLoadStrategy !== undefined) this.state.imageLoadStrategy = saved.imageLoadStrategy
      if (saved.enableImageSizePrefetch !== undefined) this.state.enableImageSizePrefetch = saved.enableImageSizePrefetch
      if (saved.threadNavMode !== undefined) this.state.threadNavMode = saved.threadNavMode
      if (saved.prefetchPageCount !== undefined) this.state.prefetchPageCount = saved.prefetchPageCount
      if (saved.videoMuted !== undefined) this.state.videoMuted = saved.videoMuted
    }
    AppStorage.setOrCreate('showSignature', this.state.showSignature)
    AppStorage.setOrCreate('imageLoadStrategy', this.state.imageLoadStrategy)
    AppStorage.setOrCreate('enableImageSizePrefetch', this.state.enableImageSizePrefetch)
    AppStorage.setOrCreate('videoMuted', this.state.videoMuted)
  }

  // ============== Blacklist ==============

  addBlacklist(entry: BlacklistEntry): void {
    this.state.blacklist = this.blacklistManager.add(entry)
    this.persistSettings()
  }

  removeBlacklist(userId: string): void {
    this.state.blacklist = this.blacklistManager.remove((u: BlacklistEntry) => u.userId === userId)
    this.persistSettings()
  }

  removeAllBlacklist(): void {
    this.state.blacklist = this.blacklistManager.clear()
    this.persistSettings()
  }

  getBlacklistIds(): Set<string> {
    const ids = new Set<string>()
    for (let i = 0; i < this.state.blacklist.length; i++) {
      ids.add(this.state.blacklist[i].userId)
    }
    return ids
  }

  getBlacklistHeaderString(): string {
    return this.state.blacklist.map(u => u.userId).join(',')
  }

  // ============== Favorites ==============

  ensureFavorites(): void {
    if (this.favoritesLoaded || !this.auth.isAuthenticated) return
    const hasCache = this.state.favorites.length > 0
    if (hasCache) {
      this.favoritesLoaded = true
    }
    setTimeout(async () => {
      await this.doRefreshFavorites()
    }, hasCache ? SettingsStore.REFRESH_DELAY : 0)
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
        this.state.favorites = favs
        this.persistSettings()
        AppStorage.setOrCreate('favVersion', (AppStorage.get<number>('favVersion') ?? 0) + 1)
      }
      this.favoritesLoaded = true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchFavorites failed')
    }
  }

  addFavorite(board: FavBoard): void {
    this.state.favorites = [...this.state.favorites, board]
    this.persistSettings()
    AppStorage.setOrCreate('favVersion', (AppStorage.get<number>('favVersion') ?? 0) + 1)
  }

  removeFavorite(fid: number): void {
    this.state.favorites = this.state.favorites.filter(f => f.fid !== fid)
    this.persistSettings()
    AppStorage.setOrCreate('favVersion', (AppStorage.get<number>('favVersion') ?? 0) + 1)
  }

  // ============== Theme ==============

  setTheme(theme: string): void {
    this.state.theme = theme
    this.applyCurrentTheme()
    this.persistSettings()
  }

  applyCurrentTheme(): void {
    let theme: string = this.state.theme
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

  // ============== Auto Checkin ==============

  setAutoCheckin(enabled: boolean): void {
    this.state.autoCheckin = enabled
    this.persistSettings()
  }

  async autoCheckinIfNeeded(): Promise<boolean> {
    if (!this.auth.isAuthenticated || !this.state.autoCheckin) {
      return false
    }
    const d: Date = new Date()
    const today: string = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    if (this.state.lastCheckinDate === today) {
      return false
    }
    try {
      const result = await checkin(this.auth.token)
      if (result.ok) {
        this.state.lastCheckinDate = today
        this.persistSettings()
        return true
      }
    } catch (e) {
      // 自动签到失败静默
    }
    return false
  }

  // ============== Font Size ==============

  setFontSize(size: number): void {
    this.state.fontSize = size
    this.persistSettings()
  }

  // ============== Domain ==============

  setDomainIndex(index: number): void {
    this.state.domainIndex = index
    this.persistSettings()
  }

  // ============== Holding Hand ==============

  setHoldingHand(value: number): void {
    this.state.holdingHand = value
    this.persistSettings()
  }

  // ============== Smart Grip ==============

  setSmartGrip(enabled: boolean): void {
    this.state.smartGrip = enabled
    this.persistSettings()
  }

  // ============== Show Signature ==============

  setShowSignature(enabled: boolean): void {
    this.state.showSignature = enabled
    AppStorage.setOrCreate('showSignature', enabled)
    this.persistSettings()
  }

  // ============== TTS ==============

  setTtsPerson(v: number): void {
    this.state.ttsPerson = v
    this.persistSettings()
  }

  setTtsSpeed(v: number): void {
    this.state.ttsSpeed = v
    this.persistSettings()
  }

  setTtsVolume(v: number): void {
    this.state.ttsVolume = v
    this.persistSettings()
  }

  setTtsPitch(v: number): void {
    this.state.ttsPitch = v
    this.persistSettings()
  }

  // ============== Image Strategy ==============

  setImageLoadStrategy(v: string): void {
    this.state.imageLoadStrategy = v
    AppStorage.setOrCreate('imageLoadStrategy', v)
    let version: number = AppStorage.get<number>('networkChangeVersion') ?? 0
    AppStorage.setOrCreate('networkChangeVersion', version + 1)
    this.persistSettings()
  }

  setEnableImageSizePrefetch(enabled: boolean): void {
    this.state.enableImageSizePrefetch = enabled
    AppStorage.setOrCreate('enableImageSizePrefetch', enabled)
    this.persistSettings()
  }

  // ============== Video Mute ==============

  /** 设置视频全局静音开关（同步 AppStorage 供 UI 响应式读取，并持久化） */
  setVideoMuted(enabled: boolean): void {
    this.state.videoMuted = enabled
    AppStorage.setOrCreate('videoMuted', enabled)
    this.persistSettings()
  }

  // ============== Thread Nav Mode ==============

  setThreadNavMode(v: string): void {
    this.state.threadNavMode = v
    this.persistSettings()
  }

  // ============== Prefetch Page Count ==============

  /** 设置预加载页数（0~5，0 表示关闭预加载） */
  setPrefetchPageCount(v: number): void {
    this.state.prefetchPageCount = Math.max(0, Math.min(5, v))
    this.persistSettings()
  }

  // ============== User Notes ==============

  addOrUpdateNote(userId: string, nickName: string, note: string): void {
    const existing: UserNoteEntry | undefined = this.state.notes.find((n: UserNoteEntry) => n.userId === userId)
    if (existing) {
      existing.note = note
      existing.nickName = nickName
    } else {
      this.state.notes = this.notesManager.add({ userId, nickName, note })
    }
    this.persistSettings()
  }

  removeNote(userId: string): void {
    this.state.notes = this.notesManager.remove((n: UserNoteEntry) => n.userId === userId)
    this.persistSettings()
  }

  removeAllNotes(): void {
    this.state.notes = this.notesManager.clear()
    this.persistSettings()
  }

  getNote(userId: string): string {
    const entry: UserNoteEntry | undefined = this.state.notes.find((n: UserNoteEntry) => n.userId === userId)
    return entry?.note ?? ''
  }

  getNoteMap(): Record<string, string> {
    const map: Record<string, string> = {}
    for (let i = 0; i < this.state.notes.length; i++) {
      map[this.state.notes[i].userId] = this.state.notes[i].note
    }
    return map
  }

  // ============== Filter Keywords ==============

  addKeyword(keyword: string): void {
    const item = new FilterKeyword()
    item.keyword = keyword
    item.enabled = true
    this.state.filterKeywords = this.filterKeywordsManager.add(item)
    this.persistSettings()
  }

  removeKeyword(keyword: string): void {
    this.state.filterKeywords = this.filterKeywordsManager.remove((k: FilterKeyword) => k.keyword === keyword)
    this.persistSettings()
  }

  toggleKeyword(keyword: string): void {
    const list = this.filterKeywordsManager.getList()
    for (let i = 0; i < list.length; i++) {
      if (list[i].keyword === keyword) {
        list[i].enabled = !list[i].enabled
        this.state.filterKeywords = [...list]
        this.persistSettings()
        return
      }
    }
  }

  removeAllKeywords(): void {
    this.filterKeywordsManager.clear()
    this.state.filterKeywords = this.filterKeywordsManager.getList()
    this.persistSettings()
  }

  getEnabledKeywords(): string[] {
    const result: string[] = []
    const list = this.state.filterKeywords
    for (let i = 0; i < list.length; i++) {
      if (list[i].enabled) {
        result.push(list[i].keyword)
      }
    }
    return result
  }
}
