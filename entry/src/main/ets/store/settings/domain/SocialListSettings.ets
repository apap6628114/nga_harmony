import { hilog } from '@kit.PerformanceAnalysisKit'
import { fetchForumFavorites } from '../../../service/NgaApi'
import { FilterListManager } from '../../../common/utils/FilterListManager'
import { SettingsContext } from '../SettingsContext'
import { FavBoard, SettingsState } from '../SettingsState'
import type { BlacklistEntry } from '../SettingsState'
import { KEY_FAV_VERSION } from '../../../common/constants/AppStorageKeys'
import { bumpAppStorageVersion } from '../../../common/utils/AppStorageVersion'

const TAG = 'SocialListSettings'
const DOMAIN = 0x0000
const REFRESH_DELAY: number = 10000

/**
 * 社交列表设置域子 store。
 *
 * 承载黑名单（BlacklistEntry）与收藏版块（FavBoard）字段及其增删查逻辑。
 * 黑名单通过 FilterListManager 维护去重，收藏版块支持从服务端刷新。
 */
export class SocialListSettings {
  private ctx: SettingsContext
  private blacklistManager: FilterListManager<BlacklistEntry> = new FilterListManager<BlacklistEntry>()
  private favoritesLoaded: boolean = false

  constructor(ctx: SettingsContext) {
    this.ctx = ctx
  }

  // ============== Blacklist ==============

  addBlacklist(entry: BlacklistEntry): void {
    this.ctx.state.blacklist = this.blacklistManager.add(entry)
    this.ctx.persist()
  }

  removeBlacklist(userId: string): void {
    this.ctx.state.blacklist = this.blacklistManager.remove((u: BlacklistEntry) => u.userId === userId)
    this.ctx.persist()
  }

  removeAllBlacklist(): void {
    this.ctx.state.blacklist = this.blacklistManager.clear()
    this.ctx.persist()
  }

  getBlacklistIds(): Set<string> {
    const ids = new Set<string>()
    for (let i = 0; i < this.ctx.state.blacklist.length; i++) {
      ids.add(this.ctx.state.blacklist[i].userId)
    }
    return ids
  }

  getBlacklistHeaderString(): string {
    return this.ctx.state.blacklist.map(u => u.userId).join(',')
  }

  // ============== Favorites ==============

  ensureFavorites(): void {
    if (this.favoritesLoaded || !this.ctx.auth!.isAuthenticated) return
    const hasCache = this.ctx.state.favorites.length > 0
    if (hasCache) {
      this.favoritesLoaded = true
    }
    setTimeout(async () => {
      await this.doRefreshFavorites()
    }, hasCache ? REFRESH_DELAY : 0)
  }

  private async doRefreshFavorites(): Promise<void> {
    if (!this.ctx.auth!.isAuthenticated) return
    try {
      const result = await fetchForumFavorites(this.ctx.auth!.token)
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
        this.ctx.state.favorites = favs
        this.ctx.persist()
        bumpAppStorageVersion(KEY_FAV_VERSION)
      }
      this.favoritesLoaded = true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchFavorites failed')
    }
  }

  addFavorite(board: FavBoard): void {
    this.ctx.state.favorites = [...this.ctx.state.favorites, board]
    this.ctx.persist()
    bumpAppStorageVersion(KEY_FAV_VERSION)
  }

  removeFavorite(fid: number): void {
    this.ctx.state.favorites = this.ctx.state.favorites.filter(f => f.fid !== fid)
    this.ctx.persist()
    bumpAppStorageVersion(KEY_FAV_VERSION)
  }

  // ============== Lifecycle ==============

  /** 从持久化对象加载黑名单与收藏（黑名单需要回填 FilterListManager） */
  load(saved: SettingsState): void {
    if (saved.favorites) this.ctx.state.favorites = saved.favorites
    if (saved.blacklist) {
      this.ctx.state.blacklist = saved.blacklist
      this.blacklistManager.init(saved.blacklist)
    }
  }

  /** 重置黑名单与收藏到默认（清空 manager、加载标志位） */
  reset(): void {
    this.blacklistManager = new FilterListManager<BlacklistEntry>()
    this.favoritesLoaded = false
  }
}
