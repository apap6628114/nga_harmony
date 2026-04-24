/**
 * 主页面 - 统一三列 Panel 架构
 * 所有断点统一使用 RouterStore 导航, 不再使用 router.pushUrl
 *
 * 第一列: 侧边栏堆栈, 固定且唯一
 * 第二列: 论坛板块堆栈, 替换模式, 堆栈深度为1
 * 第三列: 自由堆栈, 先入后出, 承载 App 大部分页面
 *
 * sm (一列): 显示内容区(activity > board > 社区网格), 不显示侧边栏
 * md (两列): 侧边栏 + 单列内容区
 * lg (三列): 侧边栏 + 板块列 + 活动列
 */

import { appStore, FavBoard } from '../store/AppStore'
import { routerStore, type BoardSlot, type NavEntry, Screen } from '../store/RouterStore'
import { getCurrentUser, getForumCategories } from '../service/NgaApi'
import { AppColors } from '../common/Constants'
import { CategoryDataSource } from '../common/LazyDataSource'
import { TopicListPanel } from './TopicListPanel'
import { ThreadPanel } from './ThreadPanel'
import { ProfilePanel } from './ProfilePanel'
import { SearchPanel } from './SearchPanel'
import { NotificationPanel } from './NotificationPanel'
import { MessageListPanel } from './MessageListPanel'
import { MessageDetailPanel } from './MessageDetailPanel'
import { BlacklistPanel } from './BlacklistPanel'
import { SettingsPanel } from './SettingsPanel'
import { BrowseHistoryPanel } from './BrowseHistoryPanel'
import { Avatar } from '../common/Avatar'
import router from '@ohos.router'

@Entry
@Component
struct MainPage {
  @State authInitialized: boolean = false
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('routerVersion') @Watch('onRouterVersionChange') routerVersion: number = 0
  @State boardSlot: BoardSlot | null = null
  @State topActivity: NavEntry | null = null

  aboutToAppear(): void {
    this.syncRouterState()
    this.checkAuth()
  }

  onBackPress(): boolean {
    if (AppStorage.get<boolean>('imageViewerVisible') ?? false) {
      AppStorage.setOrCreate('imageViewerVisible', false)
      return true
    }
    if (AppStorage.get<boolean>('profileCardVisible') ?? false) {
      AppStorage.setOrCreate('profileCardVisible', false)
      return true
    }
    if (routerStore.activityStack.length > 0) {
      routerStore.back()
      return true
    }
    if (routerStore.boardSlot) {
      if (this.currentBreakpoint === 'sm' || this.boardSlot?.type === 'search') {
        routerStore.back()
        return true
      }
      return true
    }
    return false
  }

  private onRouterVersionChange(): void {
    this.syncRouterState()
  }

  private syncRouterState(): void {
    this.boardSlot = routerStore.boardSlot
    this.topActivity = routerStore.topActivity
  }

  private async checkAuth(): Promise<void> {
    if (!appStore.auth.isAuthenticated) {
      router.replaceUrl({ url: 'pages/LoginPage' })
      return
    }

    try {
      await getCurrentUser(appStore.auth.token)
    } catch (e) {
    }
    appStore.fetchFavorites()
    this.authInitialized = true
  }

  build() {
    if (this.currentBreakpoint === 'sm') {
      this.SmLayout()
    } else if (this.currentBreakpoint === 'md') {
      this.MdLayout()
    } else {
      this.LgLayout()
    }
  }

  // ============== sm: 全屏内容区, 无固定侧边栏 ==============

  @Builder
  SmLayout() {
    Stack() {
      if (this.topActivity) {
        this.ActivityPanel()
      } else if (this.boardSlot) {
        this.BoardPanel()
      } else {
        this.MobileHomeContent()
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  MobileHomeContent() {
    Column() {
      CommunityTabContent({ currentBreakpoint: 'sm' })
    }
    .width('100%').height('100%')
  }

  // ============== md: 侧边栏 + 单列内容区 ==============

  @Builder
  MdLayout() {
    Row() {
      this.SidebarContent()

      Column() {
        if (this.topActivity) {
          this.ActivityPanel()
        } else if (this.boardSlot) {
          this.BoardPanel()
        } else {
          this.EmptyHint()
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  // ============== lg: 侧边栏 + 板块列 + 活动列 ==============

  @Builder
  LgLayout() {
    Row() {
      this.SidebarContent()

      Row() {
        if (this.boardSlot || !this.topActivity) {
          Column() {
            if (this.boardSlot) {
              this.BoardPanel()
            } else {
              this.EmptyHint()
            }
          }
          .layoutWeight(this.topActivity ? 4 : 1)
          .height('100%')
        }

        if (this.topActivity) {
          Column() {
            this.ActivityPanel()
          }
          .layoutWeight(6)
          .height('100%')
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  // ============== 内容面板 ==============

  @Builder
  BoardPanel() {
    if (this.boardSlot!.type === 'search') {
      SearchPanel()
    } else {
      TopicListPanel({
        boardFid: this.boardSlot!.fid,
        boardName: this.boardSlot!.name,
        boardStid: this.boardSlot!.stid,
        isFavorites: this.boardSlot!.fid === -9999,
        authorid: this.boardSlot!.authorid,
        favor: this.boardSlot!.favor,
        searchKey: this.boardSlot!.searchKey,
        author: this.boardSlot!.author,
        searchpost: this.boardSlot!.searchpost
      })
    }
  }

  @Builder
  ActivityPanel() {
    if (this.topActivity!.screen.type === 'thread') {
      ThreadPanel({
        threadTid: this.topActivity!.screen.tid,
        threadPid: this.topActivity!.screen.pid,
        navEntryId: this.topActivity!.id
      })
    } else if (this.topActivity!.screen.type === 'profile') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          ProfilePanel({ uid: this.topActivity!.screen.uid })
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'search') {
      SearchPanel()
    } else if (this.topActivity!.screen.type === 'notifications') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          NotificationPanel()
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'messages') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          MessageListPanel({ composeToInit: this.topActivity!.screen.composeTo })
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'messageDetail') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          MessageDetailPanel({ mid: this.topActivity!.screen.mid })
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'blacklist') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          BlacklistPanel()
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'settings') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          SettingsPanel()
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'browseHistory') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          BrowseHistoryPanel()
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else if (this.topActivity!.screen.type === 'topicList') {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          TopicListPanel({
            boardFid: this.topActivity!.screen.topicListFid,
            boardName: this.topActivity!.screen.topicListName,
            isFavorites: this.topActivity!.screen.topicListFavor === '1',
            authorid: this.topActivity!.screen.topicListAuthorid,
            favor: this.topActivity!.screen.topicListFavor,
            searchpost: this.topActivity!.screen.topicListSearchpost
          })
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
    } else {
      Column() {
        this.PanelNavBar(this.topActivity!.screen.getTitle())
        Column() {
          Text('未知页面类型').fontSize(14).fontColor(AppColors.textTertiary)
        }
        .layoutWeight(1).width('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
      .width('100%').height('100%')
    }
  }

  @Builder
  PanelNavBar(title: string) {
    Row() {
      Text('←').fontSize(22).fontColor(AppColors.primary)
        .onClick(() => routerStore.back()).padding({ left: 8, right: 8 })
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').height(44).backgroundColor(AppColors.bgTertiary)
    .border({ width: { bottom: 0.5 }, color: AppColors.separator }).alignItems(VerticalAlign.Center)
  }

  @Builder
  EmptyHint() {
    Column() {
      Text('💬').fontSize(48).opacity(0.3).margin({ bottom: 12 })
      Text('从左侧选择一个板块').fontSize(15).fontColor(AppColors.textTertiary)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.bg)
  }

  // ============== 侧边栏内容 ==============

  @Builder
  SidebarContent() {
    Column() {
      Column() {
        Avatar({
          avatar: appStore.auth.avatarUrl,
          uid: appStore.auth.uid,
          name: appStore.auth.nickName,
          avatarSize: 36
        })
        Text(appStore.auth.nickName || '未登录')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .alignItems(HorizontalAlign.Center)
      .border({ width: { bottom: 0.5 }, color: AppColors.separator })
      .onClick(() => {
        if (appStore.auth.uid) {
          routerStore.navigateActivity(Screen.profile(appStore.auth.uid))
        }
      })

      Row() {
        Text('🔍')
          .fontSize(14).margin({ right: 6 })
        Text('搜索板块、主题...')
          .fontSize(12).fontColor(AppColors.textTertiary)
      }
      .width('100%').height(36).padding({ left: 10, right: 10 })
      .backgroundColor(AppColors.bgSecondary).borderRadius(8)
      .margin({ left: 8, right: 8, top: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        routerStore.navigateSearch()
      })

      Column() {
        CommunityTabContent({ currentBreakpoint: this.currentBreakpoint })
      }
      .layoutWeight(1)
    }
    .width(180)
    .height('100%')
    .backgroundColor(AppColors.bgTertiary)
    .border({ width: { right: 0.5 }, color: AppColors.separator })
  }
}

// ============== 社区 Tab 内容 ==============

@Component
struct CommunityTabContent {
  @State isLoading: boolean = true
  @State collapsedCatIds: string[] = []
  @State favoritesList: FavBoard[] = []
  @Prop currentBreakpoint: string = 'sm'
  @StorageProp('routerVersion') routerVersion: number = 0
  @StorageProp('favVersion') @Watch('onFavVersionChange') favVersion: number = 0
  categories: import('../model/Forum').Category[] = []
  private categoriesDataSource: CategoryDataSource = new CategoryDataSource()

  aboutToAppear(): void {
    this.syncFavorites()
    this.loadCategories()
  }

  private onFavVersionChange(): void {
    this.syncFavorites()
  }

  private syncFavorites(): void {
    this.favoritesList = [...appStore.settings.favorites]
  }

  private async loadCategories(): Promise<void> {
    try {
      const result = await getForumCategories(appStore.auth.token)
      if (result.ok) {
        this.categories = result.data
        this.categoriesDataSource.replaceAll(this.categories)
      }
    } catch (e) {
    }
    this.isLoading = false
  }

  build() {
    Scroll() {
      Column() {
        if (this.currentBreakpoint === 'sm') {
          this.MobileContent()
        } else {
          this.SidebarListContent()
        }
      }
      .width('100%')
      .padding({ bottom: 8 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  private isFavBoard(fid: number): boolean {
    for (const f of this.favoritesList) {
      if (f.fid === fid) return true
    }
    return false
  }

  private handleToggleFav(fid: number, name: string): void {
    if (this.isFavBoard(fid)) {
      appStore.removeFavorite(fid)
    } else {
      const fb = new FavBoard()
      fb.fid = fid
      fb.stid = fid
      fb.name = name
      appStore.addFavorite(fb)
    }
  }

  @Builder
  SidebarListContent() {
    if (this.favoritesList.length > 0) {
      Column() {
        Text('收藏板块')
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor(AppColors.textSecondary)
          .width('100%').padding({ left: 8, top: 8, bottom: 4 })

        ForEach(this.favoritesList, (fav: FavBoard) => {
          Row() {
            Image(`https://img4.nga.178.com/ngabbs/nga_classic/f/app/${fav.fid}.png`)
              .width(20).height(20).borderRadius(5).objectFit(ImageFit.Cover)
              .onError(() => {})
            Text(fav.name)
              .fontSize(12).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 6 }).layoutWeight(1)
          }
          .width('100%').height(32)
          .padding({ left: 8, right: 8 })
          .alignItems(VerticalAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.isActiveBoard(fav.fid) ? AppColors.bgSecondary : Color.Transparent)
          .onClick(() => {
            routerStore.navigateForum(fav.fid, fav.name)
          })
        })
      }
      .width('100%')
    }

    if (this.isLoading) {
      Column() {
        LoadingProgress().width(24).height(24).color(AppColors.textTertiary)
      }
      .width('100%').height(60)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    } else {
      ForEach(this.categories, (cat: import('../model/Forum').Category) => {
        this.SidebarCategorySection(cat)
      })
    }
  }

  @Builder
  SidebarCategorySection(cat: import('../model/Forum').Category) {
    Column() {
      Row() {
        Text('›')
          .fontSize(14).fontColor(AppColors.textTertiary).margin({ right: 6 })
          .rotate({ angle: this.isCatCollapsed(cat) ? 0 : 90 })
        Text(cat.name)
          .fontSize(13).fontWeight(FontWeight.Bold)
        Text(this.collectBoardCount(cat).toString())
          .fontSize(11).fontColor(AppColors.textTertiary).margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggleCat(cat.name)
      })

      if (!this.isCatCollapsed(cat)) {
        ForEach(this.collectBoards(cat), (board: import('../model/Forum').BoardContent) => {
          Row() {
            Image(`https://img4.nga.178.com/ngabbs/nga_classic/f/app/${board.fid}.png`)
              .width(18).height(18).borderRadius(4).objectFit(ImageFit.Cover)
              .onError(() => {})
            Text(board.name)
              .fontSize(12).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 6 }).layoutWeight(1)
            Text(this.isFavBoard(board.fid) ? '★' : '☆')
              .fontSize(12)
              .fontColor(this.isFavBoard(board.fid) ? AppColors.primary : AppColors.textTertiary)
              .margin({ left: 4 })
              .onClick(() => {
                this.handleToggleFav(board.fid, board.name)
              })
          }
          .width('100%').height(30)
          .padding({ left: 22, right: 8 })
          .alignItems(VerticalAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.isActiveBoard(board.fid) ? AppColors.bgSecondary : Color.Transparent)
          .onClick(() => {
            routerStore.navigateForum(board.fid, board.name)
          })
        })
      }
    }
    .width('100%')
    .border({ width: { top: 0.5 }, color: AppColors.separator })
  }

  // ============== 移动端网格模式 (sm) ==============

  @Builder
  MobileContent() {
    Row() {
      Text('🔍')
        .fontSize(16).margin({ right: 8 })
      Text('搜索板块、主题...')
        .fontSize(15).fontColor(AppColors.textTertiary)
    }
    .width('92%').height(40).padding({ left: 12, right: 12 })
    .backgroundColor(AppColors.bgSecondary).borderRadius(10)
    .margin({ top: 12, bottom: 12 }).alignItems(VerticalAlign.Center)
    .onClick(() => {
      routerStore.navigateSearch()
    })

    if (this.favoritesList.length > 0) {
      this.FavoritesGrid()
    }

    if (this.isLoading) {
      Column() {
        LoadingProgress().width(24).height(24).color(AppColors.textTertiary)
        Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 12 })
      }
      .width('100%').height(200)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    } else {
      List() {
        LazyForEach(this.categoriesDataSource, (cat: import('../model/Forum').Category) => {
          ListItem() {
            this.CategoryGrid(cat)
          }
        }, (cat: import('../model/Forum').Category) => cat.id)
      }
      .width('100%')
      .divider({ strokeWidth: 8, color: Color.Transparent })
    }
  }

  @Builder
  FavoritesGrid() {
    Column() {
      Row() {
        Text('我的收藏')
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(AppColors.primary)
        Text(`${this.favoritesList.length} 个板块`)
          .fontSize(11).fontColor(AppColors.textTertiary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })
      .justifyContent(FlexAlign.SpaceBetween)

      GridRow({ columns: { sm: 4, md: 4, lg: 3 }, gutter: 8 }) {
        ForEach(this.favoritesList, (fav: FavBoard) => {
          GridCol() {
            Column() {
              Stack() {
                Image(`https://img4.nga.178.com/ngabbs/nga_classic/f/app/${fav.fid}.png`)
                  .width(44).height(44).borderRadius(12).objectFit(ImageFit.Cover)
                  .onError(() => {})
              }
              .width(44).height(44).borderRadius(12).backgroundColor(AppColors.bgSecondary)

              Text(fav.name)
                .fontSize(11).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 56 })
            }
            .padding({ top: 8, bottom: 8 }).alignItems(HorizontalAlign.Center)
            .onClick(() => {
              routerStore.navigateForum(fav.fid, fav.name)
            })
          }
        })
      }
      .width('100%').padding({ left: 8, right: 8, bottom: 14 })
    }
    .width('92%').backgroundColor(AppColors.bgTertiary).borderRadius(12).margin({ bottom: 8 })
  }

  @Builder
  CategoryGrid(cat: import('../model/Forum').Category) {
    Column() {
      Row() {
        Text(cat.name).fontSize(13).fontWeight(FontWeight.Bold)
        Text(this.collectBoardCount(cat).toString())
          .fontSize(11).fontColor(AppColors.textTertiary).margin({ left: 6 })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      GridRow({ columns: { sm: 4, md: 4, lg: 3 }, gutter: 8 }) {
        ForEach(this.collectBoards(cat), (board: import('../model/Forum').BoardContent) => {
          GridCol() {
            Column() {
              Stack() {
                Image(`https://img4.nga.178.com/ngabbs/nga_classic/f/app/${board.fid}.png`)
                  .width(40).height(40).borderRadius(10).objectFit(ImageFit.Cover)
                  .onError(() => {})
              }
              .width(40).height(40).borderRadius(10).backgroundColor(AppColors.bgSecondary)

              Text(board.name)
                .fontSize(11).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 52 })
                .fontColor(AppColors.textPrimary)
            }
            .padding({ top: 10, bottom: 10 }).alignItems(HorizontalAlign.Center)
            .onClick(() => {
              routerStore.navigateForum(board.fid, board.name)
            })
          }
        })
      }
      .width('100%').padding({ left: 6, right: 6 })
      .backgroundColor(AppColors.bgTertiary).borderRadius(12)
    }
    .width('92%')
  }

  // ============== 工具方法 ==============

  private isActiveBoard(fid: number): boolean {
    return routerStore.boardSlot !== null && routerStore.boardSlot.fid === fid
  }

  private isCatCollapsed(cat: import('../model/Forum').Category): boolean {
    return this.collapsedCatIds.indexOf(cat.name) >= 0
  }

  private toggleCat(catId: string): void {
    const idx = this.collapsedCatIds.indexOf(catId)
    if (idx >= 0) {
      const next = [...this.collapsedCatIds]
      next.splice(idx, 1)
      this.collapsedCatIds = next
    } else {
      this.collapsedCatIds = [...this.collapsedCatIds, catId]
    }
  }

  private collectBoards(cat: import('../model/Forum').Category): import('../model/Forum').BoardContent[] {
    const seen = new Set<number>()
    const boards: import('../model/Forum').BoardContent[] = []
    if (cat.sub && Array.isArray(cat.sub)) {
      for (const sub of cat.sub) {
        if (sub.content && Array.isArray(sub.content)) {
          for (const board of sub.content) {
            if (!seen.has(board.fid)) {
              seen.add(board.fid)
              boards.push(board)
            }
          }
        }
      }
    }
    return boards
  }

  private collectBoardCount(cat: import('../model/Forum').Category): number {
    return this.collectBoards(cat).length
  }
}
