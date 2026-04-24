/**
 * 路由状态管理 - 复刻 React router.ts
 * 三列适配模式: boardSlot(中间列) + activityStack(右侧列)
 * 所有断点统一使用 RouterStore 导航, 不再使用 router.pushUrl
 * 使用 AppStorage 驱动 UI 响应式更新
 */

export type LayoutMode = 'sm' | 'md' | 'lg'
export type SidebarTab = 'community' | 'me'

export class BoardSlot {
  fid: number = 0
  name: string = ''
  stid: string = ''
  authorid: string = ''
  favor: string = ''
  searchKey: string = ''
  author: string = ''
  searchpost: string = ''

  constructor(
    fid: number, name: string, stid: string = '',
    authorid: string = '', favor: string = '',
    searchKey: string = '', author: string = '',
    searchpost: string = ''
  ) {
    this.fid = fid
    this.name = name
    this.stid = stid
    this.authorid = authorid
    this.favor = favor
    this.searchKey = searchKey
    this.author = author
    this.searchpost = searchpost
  }
}

export type ScreenType =
  | 'thread'
  | 'profile'
  | 'notifications'
  | 'messages'
  | 'messageDetail'
  | 'search'
  | 'blacklist'
  | 'settings'
  | 'browseHistory'
  | 'topicList'

export class Screen {
  type: ScreenType = 'thread'
  tid: string = ''
  threadPage: number = 1
  pid: string = ''
  uid: string = ''
  mid: string = ''
  messagePage: number = 1
  composeTo: string = ''
  topicListName: string = ''
  topicListFid: number = 0
  topicListAuthorid: string = ''
  topicListFavor: string = ''
  topicListSearchpost: string = ''

  static thread(tid: string, page: number = 1, pid: string = ''): Screen {
    const s = new Screen()
    s.type = 'thread'
    s.tid = tid
    s.threadPage = page
    s.pid = pid
    return s
  }

  static profile(uid: string): Screen {
    const s = new Screen()
    s.type = 'profile'
    s.uid = uid
    return s
  }

  static messageDetail(mid: string, page: number = 1): Screen {
    const s = new Screen()
    s.type = 'messageDetail'
    s.mid = mid
    s.messagePage = page
    return s
  }

  static messages(composeTo: string = ''): Screen {
    const s = new Screen()
    s.type = 'messages'
    s.composeTo = composeTo
    return s
  }

  static search(): Screen {
    const s = new Screen()
    s.type = 'search'
    return s
  }

  static notifications(): Screen {
    const s = new Screen()
    s.type = 'notifications'
    return s
  }

  static blacklist(): Screen {
    const s = new Screen()
    s.type = 'blacklist'
    return s
  }

  static settings(): Screen {
    const s = new Screen()
    s.type = 'settings'
    return s
  }

  static browseHistory(): Screen {
    const s = new Screen()
    s.type = 'browseHistory'
    return s
  }

  static topicList(
    name: string, fid: number = 0,
    authorid: string = '', favor: string = '',
    searchpost: string = ''
  ): Screen {
    const s = new Screen()
    s.type = 'topicList'
    s.topicListName = name
    s.topicListFid = fid
    s.topicListAuthorid = authorid
    s.topicListFavor = favor
    s.topicListSearchpost = searchpost
    return s
  }

  getTitle(): string {
    switch (this.type) {
      case 'thread': return '帖子'
      case 'profile': return '个人主页'
      case 'notifications': return '通知'
      case 'messages': return '私信'
      case 'messageDetail': return '私信'
      case 'search': return '搜索'
      case 'blacklist': return '黑名单管理'
      case 'settings': return '设置'
      case 'browseHistory': return '浏览历史'
      case 'topicList': return this.topicListName || '主题列表'
      default: return ''
    }
  }
}

export class NavEntry {
  id: number = 0
  screen: Screen = new Screen()

  constructor(id: number, screen: Screen) {
    this.id = id
    this.screen = screen
  }
}

let nextNavId = 0

class RouterStoreClass {
  private _sidebarTab: SidebarTab = 'community'
  get sidebarTab(): SidebarTab { return this._sidebarTab }

  private _boardSlot: BoardSlot | null = null
  get boardSlot(): BoardSlot | null { return this._boardSlot }

  private _activityStack: NavEntry[] = []
  get activityStack(): NavEntry[] { return this._activityStack }
  get topActivity(): NavEntry | null {
    return this._activityStack.length > 0 ? this._activityStack[this._activityStack.length - 1] : null
  }

  private _version: number = 0
  get version(): number { return this._version }

  private bump(): void {
    this._version++
    AppStorage.setOrCreate('routerVersion', this._version)
  }

  setSidebarTab(tab: SidebarTab): void {
    if (this._sidebarTab === tab) return
    this._sidebarTab = tab
    this.bump()
  }

  setBoardSlot(board: BoardSlot | null): void {
    this._boardSlot = board
    this.bump()
  }

  navigateForum(
    fid: number, name: string, stid: string = '',
    authorid: string = '', favor: string = '',
    searchKey: string = '', author: string = '',
    searchpost: string = ''
  ): void {
    this._boardSlot = new BoardSlot(fid, name, stid, authorid, favor, searchKey, author, searchpost)
    this._activityStack = []
    this.bump()
  }

  navigateActivity(screen: Screen, replace: boolean = false): void {
    const stack = [...this._activityStack]
    const entry = new NavEntry(++nextNavId, screen)

    if (replace && stack.length > 0) {
      stack[stack.length - 1] = entry
    } else if (screen.type === 'thread') {
      const top = stack.length > 0 ? stack[stack.length - 1] : null
      if (top && top.screen.type === 'thread') {
        stack[stack.length - 1] = entry
      } else {
        stack.push(entry)
      }
    } else {
      stack.push(entry)
    }
    this._activityStack = stack
    this.bump()
  }

  back(): void {
    if (this._activityStack.length > 0) {
      this._activityStack = this._activityStack.slice(0, -1)
      this.bump()
      return
    }
    if (this._boardSlot) {
      this._boardSlot = null
      this.bump()
    }
  }

  reset(tab: SidebarTab = 'community'): void {
    this._sidebarTab = tab
    this._boardSlot = null
    this._activityStack = []
    this.bump()
  }
}

export const routerStore = new RouterStoreClass()
