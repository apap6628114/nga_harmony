import { hilog } from '@kit.PerformanceAnalysisKit'
import { ConfigurationConstant, Context } from '@kit.AbilityKit'
import { fetchForumFavorites, getForumCategories, getUserProfile } from '../service/NgaApi'
import type { Category } from '../model/Forum'
import type { ProfileData } from '../model/User'
import { PreferencesStore } from './PreferencesStore'
import { FilterKeyword } from '../model/FilterKeyword'
import { FilterListManager } from './FilterListManager'

const TAG = 'AppStore'
const DOMAIN = 0x0000

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

class AppStoreClass {
  private store: PreferencesStore = new PreferencesStore()

  auth: AuthState = new AuthState()
  settings: SettingsState = new SettingsState()
  toast: ToastState = new ToastState()
  private toastTimer: number = -1
  private context?: Context

  cachedCategories: Category[] = []
  private categoriesVersion: number = 0
  private categoriesRefreshing: boolean = false

  private blacklistManager: FilterListManager<BlacklistEntry> = new FilterListManager<BlacklistEntry>()

  private filterKeywordsManager: FilterListManager<FilterKeyword> = new FilterListManager<FilterKeyword>()

  private profileCache: Record<string, ProfileData> = {}
  private profileVersion: number = 0
  private refreshingUids: Set<string> = new Set()

  private static readonly REFRESH_DELAY: number = 10000

  async init(context: Context): Promise<void> {
    try {
      this.context = context
      await this.store.init(context, 'nga_app_store')
      await this.migrateAuthIfNeeded()
      await this.loadAuth()
      await this.loadCachedCategories()
      if (this.auth.uid) {
        await this.loadUserSettings()
        await this.loadCachedProfiles()
      }
      this.applyCurrentTheme()
      hilog.info(DOMAIN, TAG, 'AppStore initialized')
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'AppStore init failed: %{public}s', JSON.stringify(e))
    }
  }

  private settingsKey(): string {
    return `settings_${this.auth.uid}`
  }

  private profilesKey(): string {
    return `cached_profiles_${this.auth.uid}`
  }

  private resetUserState(): void {
    this.settings = new SettingsState()
    this.blacklistManager = new FilterListManager<BlacklistEntry>()
    this.filterKeywordsManager = new FilterListManager<FilterKeyword>()
    this.profileCache = {}
    this.favoritesLoaded = false
    this.refreshingUids = new Set()
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
    this.store.putJSON('auth', data)
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

  private applyCurrentTheme(): void {
    let theme: string = this.settings.theme
    // 兼容旧数据：original/white 统一映射到 light
    if (theme === 'original' || theme === 'white') {
      theme = 'light'
    }
    let mode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    if (theme === 'dark') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    }
    try {
      this.context?.getApplicationContext().setColorMode(mode)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(err))
    }
    AppStorage.setOrCreate('themeName', theme)
  }

  private persistSettings(): void {
    if (!this.auth.uid) return
    this.store.putJSON(this.settingsKey(), this.settings)
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
      if (saved.filterKeywords) {
        this.settings.filterKeywords = saved.filterKeywords
        this.filterKeywordsManager.init(saved.filterKeywords)
      }
      if (saved.fontSize) this.settings.fontSize = saved.fontSize
      if (saved.domainIndex) this.settings.domainIndex = saved.domainIndex
      if (saved.theme) this.settings.theme = saved.theme
    }
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
    this.store.putJSON('cached_categories', this.cachedCategories)
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

  private async loadCachedProfiles(): Promise<void> {
    if (!this.auth.uid) return
    const saved = await this.store.getJSON<Record<string, ProfileData>>(this.profilesKey())
    if (saved) {
      this.profileCache = saved
      hilog.info(DOMAIN, TAG, 'Loaded cached profiles: %{public}d', Object.keys(saved).length)
    }
  }

  private persistProfiles(): void {
    if (!this.auth.uid) return
    this.store.putJSON(this.profilesKey(), this.profileCache)
  }

  getCachedProfile(uid: string): ProfileData | null {
    return this.profileCache[uid] ?? null
  }

  ensureProfile(uid: string): void {
    if (this.refreshingUids.has(uid)) return
    this.refreshingUids.add(uid)
    const hasCache = !!this.profileCache[uid]
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
        const oldJson = this.profileCache[uid] ? JSON.stringify(this.profileCache[uid]) : ''
        this.profileCache[uid] = result.data
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

  // ============== Blacklist helper string ==============

  getBlacklistHeaderString(): string {
    return this.settings.blacklist.map(u => u.userId).join(',')
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
}

export const appStore = new AppStoreClass()
