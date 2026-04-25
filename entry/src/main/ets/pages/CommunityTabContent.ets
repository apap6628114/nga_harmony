import { appStore, FavBoard } from '../store/AppStore'
import { routerStore, RouterStoreClass } from '../store/RouterStore'
import { AppColors } from '../common/Constants'
import { CategoryDataSource, SidebarDataSource, SidebarSection, SidebarBoardItem } from '../common/LazyDataSource'
import type { Category, BoardContent } from '../model/Forum'

@Component
export struct CommunityTabContent {
  @State isLoading: boolean = true
  @State favoritesList: FavBoard[] = []
  @State private router: RouterStoreClass = routerStore
  @Prop currentBreakpoint: string = 'sm'
  @StorageProp('favVersion') @Watch('onFavVersionChange') favVersion: number = 0
  @StorageProp('catVersion') @Watch('onCatVersionChange') catVersion: number = 0
  categories: Category[] = []
  private categoriesDataSource: CategoryDataSource = new CategoryDataSource()
  private sidebarDataSource: SidebarDataSource = new SidebarDataSource()

  aboutToAppear(): void {
    this.syncFavorites()
    if (appStore.cachedCategories.length > 0) {
      this.categories = appStore.cachedCategories
      this.categoriesDataSource.replaceAll(this.categories)
      this.rebuildSidebarSections()
      this.isLoading = false
    }
    appStore.ensureCategories()
  }

  private onFavVersionChange(): void {
    this.syncFavorites()
    this.rebuildSidebarSections()
  }

  private onCatVersionChange(): void {
    this.categories = appStore.cachedCategories
    this.categoriesDataSource.replaceAll(this.categories)
    this.rebuildSidebarSections()
    if (this.isLoading) {
      this.isLoading = false
    }
  }

  private syncFavorites(): void {
    this.favoritesList = [...appStore.settings.favorites]
  }

  private rebuildSidebarSections(): void {
    const prevCollapsed = new Map<string, boolean>()
    const count = this.sidebarDataSource.totalCount()
    for (let i = 0; i < count; i++) {
      const s = this.sidebarDataSource.getData(i)
      prevCollapsed.set(s.id, s.collapsed)
    }
    const sections: SidebarSection[] = []
    if (this.favoritesList.length > 0) {
      const favItems: SidebarBoardItem[] = []
      for (const fav of this.favoritesList) {
        favItems.push({ fid: fav.fid, stid: fav.stid, name: fav.name })
      }
      sections.push({ id: '__fav__', name: '收藏板块', items: favItems, collapsed: false, collapsible: false })
    }
    for (const cat of this.categories) {
      const boards: SidebarBoardItem[] = []
      const seen = new Set<number>()
      if (cat.sub && Array.isArray(cat.sub)) {
        for (const sub of cat.sub) {
          if (sub.content && Array.isArray(sub.content)) {
            for (const board of sub.content) {
              if (!seen.has(board.fid)) {
                seen.add(board.fid)
                boards.push({ fid: board.fid, stid: board.stid, name: board.name })
              }
            }
          }
        }
      }
      const prev = prevCollapsed.get(cat.id)
      sections.push({ id: cat.id, name: cat.name, items: boards, collapsed: prev !== undefined ? prev : true, collapsible: true })
    }
    this.sidebarDataSource.replaceAll(sections)
  }

  build() {
    if (this.currentBreakpoint === 'sm') {
      Scroll() {
        Column() {
          this.MobileContent()
        }
        .width('100%')
        .padding({ bottom: 8 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    } else {
      this.SidebarListContent()
    }
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
    if (this.isLoading) {
      Column() {
        LoadingProgress().width(24).height(24).color(AppColors.textTertiary)
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    } else {
      List({ space: 0 }) {
        LazyForEach(this.sidebarDataSource, (section: SidebarSection) => {
          ListItemGroup({
            header: this.SidebarSectionHeader(section)
          }) {
            if (!section.collapsed) {
              ForEach(section.items, (item: SidebarBoardItem) => {
                ListItem() {
                  Row() {
                    Image(`https://img4.nga.178.com/ngabbs/nga_classic/f/app/${item.fid}.png`)
                      .width(section.collapsible ? 18 : 20)
                      .height(section.collapsible ? 18 : 20)
                      .borderRadius(section.collapsible ? 4 : 5)
                      .objectFit(ImageFit.Cover)
                      .onError(() => {})
                    Text(item.name)
                      .fontSize(12).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ left: 6 }).layoutWeight(1)
                    if (section.collapsible) {
                      Text(this.isFavBoard(item.fid) ? '★' : '☆')
                        .fontSize(12)
                        .fontColor(this.isFavBoard(item.fid) ? AppColors.primary : AppColors.textTertiary)
                        .margin({ left: 4 })
                        .onClick(() => {
                          this.handleToggleFav(item.fid, item.name)
                        })
                    }
                  }
                  .width('100%').height(section.collapsible ? 30 : 32)
                  .padding({ left: section.collapsible ? 22 : 8, right: 8 })
                  .alignItems(VerticalAlign.Center)
                  .borderRadius(8)
                  .backgroundColor(this.isActiveBoard(item.fid) ? AppColors.bgSecondary : Color.Transparent)
                  .onClick(() => {
                    routerStore.navigateForum(item.fid, item.name)
                  })
                }
              }, (item: SidebarBoardItem) => `${item.fid}`)
            }
          }
        }, (section: SidebarSection) => `${section.id}_${section.collapsed}`)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .cachedCount(2)
      .divider({ strokeWidth: 0.5, color: AppColors.separator })
    }
  }

  @Builder
  SidebarSectionHeader(section: SidebarSection) {
    Row() {
      if (section.collapsible) {
        Text('›')
          .fontSize(14).fontColor(AppColors.textTertiary).margin({ right: 6 })
          .rotate({ angle: section.collapsed ? 0 : 90 })
      }
      Text(section.name)
        .fontSize(section.collapsible ? 13 : 11)
        .fontWeight(FontWeight.Bold)
        .fontColor(section.collapsible ? AppColors.textPrimary : AppColors.textSecondary)
      if (section.collapsible) {
        Text(section.items.length.toString())
          .fontSize(11).fontColor(AppColors.textTertiary).margin({ left: 6 })
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (section.collapsible) {
        this.toggleSidebarSection(section)
      }
    })
  }

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
        LazyForEach(this.categoriesDataSource, (cat: Category) => {
          ListItem() {
            this.CategoryGrid(cat)
          }
        }, (cat: Category) => cat.id)
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
  CategoryGrid(cat: Category) {
    Column() {
      Row() {
        Text(cat.name).fontSize(13).fontWeight(FontWeight.Bold)
        Text(this.collectBoardCountForCat(cat).toString())
          .fontSize(11).fontColor(AppColors.textTertiary).margin({ left: 6 })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      GridRow({ columns: { sm: 4, md: 4, lg: 3 }, gutter: 8 }) {
        ForEach(this.collectBoardsFromCat(cat), (board: BoardContent) => {
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

  private isActiveBoard(fid: number): boolean {
    return this.router.boardSlot !== null && this.router.boardSlot.fid === fid
  }

  private collectBoardsFromCat(cat: Category): BoardContent[] {
    const seen = new Set<number>()
    const boards: BoardContent[] = []
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

  private collectBoardCountForCat(cat: Category): number {
    return this.collectBoardsFromCat(cat).length
  }

  private toggleSidebarSection(section: SidebarSection): void {
    const idx = this.sidebarDataSource.indexOf(section.id)
    if (idx < 0) {
      return
    }
    const updated: SidebarSection = {
      id: section.id,
      name: section.name,
      items: section.items,
      collapsed: !section.collapsed,
      collapsible: section.collapsible
    }
    this.sidebarDataSource.updateSection(idx, updated)
  }
}
