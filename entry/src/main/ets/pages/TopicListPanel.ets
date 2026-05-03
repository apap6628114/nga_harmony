/**
 * 主题列表面板 - 统一版, 所有断点共用
 * 第二列(板块堆栈) 或 第三列(活动栈) 均可使用
 * 点击主题通过 routerStore 导航
 */

import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { getTopicList, createTopicListParams, TopicListParams, TopicListResult, removeFavorite } from '../service/NgaApi'
import { AppColors, FONT_COLORS, SORT_MODES, SortMode, BreakpointType } from '../common/Constants'
import { formatTime, unescapeHtml } from '../common/Utils'
import { PanelNavBar } from '../common/PanelNavBar'
import { ThreadDataSource } from '../common/LazyDataSource'
import { AnonymousName } from '../common/AnonymousName'

enum HoldingHandStatus {
  NOT_HELD = 0,
  LEFT_HAND_HELD = 1,
  RIGHT_HAND_HELD = 2,
  BOTH_HANDS_HELD = 3,
  UNKNOWN_STATUS = 16
}

@Component
export struct TopicListPanel {
  @Prop @Watch('onBoardChanged') boardFid: number = 0
  @Prop boardName: string = ''
  @Prop boardStid: string = ''
  @Prop isFavorites: boolean = false
  @Prop authorid: string = ''
  @Prop favor: string = ''
  @Prop searchKey: string = ''
  @Prop author: string = ''
  @Prop searchpost: string = ''
  @Prop showBack: boolean = true
  @State holdingStatus: HoldingHandStatus = appStore.settings.holdingHand as HoldingHandStatus
  @State holdingDetected: boolean = false
  @State isLoading: boolean = true
  @State isLoadingMore: boolean = false
  @State hasError: boolean = false
  @State errorMsg: string = ''
  @State threads: object[] = []
  private threadsDataSource: ThreadDataSource = new ThreadDataSource()
  @State currentPage: number = 1
  @State totalPages: number = 0
  @State sortMode: string = 'latest'
  @State showSort: boolean = true
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('unreadNotiCount') unreadNotiCount: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0

  private scroller: Scroller = new Scroller()
  private prefetchedThreads: object[] = []
  private prefetchedPage: number = 0
  private prefetchInProgress: boolean = false

  private holdingCallback: Callback<HoldingHandStatus> = (data: HoldingHandStatus): void => {
    if (this.holdingDetected) {
      animateTo({ duration: 300, curve: Curve.EaseInOut }, (): void => {
        this.holdingStatus = data
      })
    } else {
      this.holdingStatus = data
      this.holdingDetected = true
    }
    if (appStore.settings.holdingHand !== data) {
      appStore.settings.holdingHand = data
      appStore.persistSettings()
    }
  }

  private startHoldingHandMonitoring(): void {
    try {
      motion.on('holdingHandChanged', this.holdingCallback)
    } catch (err) {
      console.error('startHolding fail:', (err as BusinessError).code)
    }
  }

  private stopHoldingHandMonitoring(): void {
    try {
      motion.off('holdingHandChanged', this.holdingCallback)
    } catch (err) {
      console.error('stopHolding fail:', (err as BusinessError).code)
    }
  }

  aboutToAppear(): void {
    this.showSort = !this.authorid && !this.favor
    this.loadTopics(1)
    appStore.refreshUnreadCount()
    this.startHoldingHandMonitoring()
  }

  aboutToDisappear(): void {
    this.stopHoldingHandMonitoring()
  }

  private onBoardChanged(): void {
    this.threads = []
    this.threadsDataSource.clear()
    this.currentPage = 1
    this.totalPages = 0
    this.hasError = false
    this.sortMode = 'latest'
    this.showSort = !this.authorid && !this.favor
    this.loadTopics(1)
    appStore.refreshUnreadCount()
  }

  private buildTopicParams(page: number): TopicListParams {
    const params: TopicListParams = createTopicListParams()
    params.page = String(page)
    if (this.isFavorites || this.favor) {
      params.favor = '1'
    } else {
      if (this.boardFid) params.fid = String(this.boardFid)
      if (this.boardStid) params.stid = this.boardStid
    }
    if (this.authorid) params.authorid = this.authorid
    if (this.searchKey) params.key = this.searchKey
    if (this.author) params.author = this.author
    if (this.searchpost) params.searchpost = this.searchpost
    if (this.showSort) {
      if (this.sortMode === 'recommend') {
        params.recommend = '1'
      } else if (this.sortMode === 'hot') {
        params.recommend = '1'
        params.twentyfour = '1'
      }
    }
    return params
  }

  private mergeThreads(list: object[]): void {
    const existingTids: Set<number> = new Set()
    for (let i = 0; i < this.threads.length; i++) {
      const t: number = Number((this.threads[i] as Record<string, Object>)['tid'] ?? 0)
      if (t) existingTids.add(t)
    }
    const deduped: object[] = []
    for (let i = 0; i < list.length; i++) {
      const t: number = Number((list[i] as Record<string, Object>)['tid'] ?? 0)
      if (!existingTids.has(t)) {
        deduped.push(list[i])
        existingTids.add(t)
      }
    }
    if (deduped.length > 0) {
      const arr: object[] = []
      for (let i = 0; i < this.threads.length; i++) arr.push(this.threads[i])
      for (let i = 0; i < deduped.length; i++) arr.push(deduped[i])
      this.threads = arr
      this.threadsDataSource.appendAll(deduped)
    }
  }

  private async loadTopics(page: number): Promise<void> {
    if (page === 1) {
      this.isLoading = true
      this.hasError = false
      this.clearPrefetch()
    } else {
      this.isLoadingMore = true
    }

    const params: TopicListParams = this.buildTopicParams(page)

    try {
      const result: TopicListResult = await getTopicList(appStore.auth.token, params, appStore.getBlacklistIds(), appStore.getEnabledKeywords())
      if (result.ok && result.data) {
        const list: object[] = result.data.threadPageList
        if (page === 1) {
          this.threads = list
          this.threadsDataSource.replaceAll(list)
        } else {
          this.mergeThreads(list)
        }
        this.currentPage = page
        this.totalPages = result.data.pagination.totalPages
        this.triggerPrefetch()
      } else if (page === 1) {
        this.hasError = true
        this.errorMsg = result.error || '加载失败'
      }
    } catch (e) {
      if (page === 1) {
        this.hasError = true
        this.errorMsg = (e as Error).message || '加载失败'
      }
    }
    this.isLoading = false
    this.isLoadingMore = false
  }

  private clearPrefetch(): void {
    this.prefetchedThreads = []
    this.prefetchedPage = 0
  }

  private triggerPrefetch(): void {
    const nextPage: number = this.currentPage + 1
    if (nextPage > this.totalPages || this.prefetchInProgress) return
    if (this.prefetchedPage === nextPage) return
    this.startPrefetch(nextPage)
  }

  private async startPrefetch(page: number): Promise<void> {
    this.prefetchInProgress = true
    try {
      const params: TopicListParams = this.buildTopicParams(page)
      const result: TopicListResult = await getTopicList(appStore.auth.token, params, appStore.getBlacklistIds(), appStore.getEnabledKeywords())
      if (result.ok && result.data) {
        this.prefetchedThreads = result.data.threadPageList
        this.prefetchedPage = page
      }
    } catch (e) {
      this.clearPrefetch()
    }
    this.prefetchInProgress = false
  }

  private getSubjectFontColor(titleFont: string): ResourceColor {
    const num = Number(titleFont) || 0
    const color = num & 0x1f
    if (FONT_COLORS[color]) return FONT_COLORS[color]
    return AppColors.textPrimary
  }

  private isSubjectBold(titleFont: string): boolean {
    return (Number(titleFont) & 32) !== 0
  }

  private isSubjectItalic(titleFont: string): boolean {
    return (Number(titleFont) & 64) !== 0
  }

  private getTypeTags(type: number): string {
    if (type & 1024) return '[锁定]'
    return ''
  }

  private async handleRemoveFav(tid: number): Promise<void> {
    try {
      const result = await removeFavorite(appStore.auth.token, tid, 0, 1)
      if (result.ok) {
        const filtered = this.threads.filter((t: object) => Number((t as Record<string, Object>)['tid']) !== tid)
        this.threads = filtered
        this.threadsDataSource.replaceAll(filtered)
        appStore.showToast('已取消收藏')
      } else {
        appStore.showToast(result.error || '取消收藏失败')
      }
    } catch (e) {
      appStore.showToast('取消收藏失败')
    }
  }

  build() {
    Stack() {
      Column() {
        if (this.isLoading) {
          Row().width('100%').height(44 + this.statusBarHeight)
          Column() {
            LoadingProgress().width(28).height(28).color(AppColors.textTertiary)
            Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 8 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.hasError) {
          Row().width('100%').height(44 + this.statusBarHeight)
          Column() {
            Text(this.errorMsg || '加载失败').fontSize(14).fontColor(AppColors.textTertiary).margin({ bottom: 12 })
            Button('重试').fontSize(14).fontColor(AppColors.primary).backgroundColor(AppColors.bgSecondary).borderRadius(10)
              .onClick(() => this.loadTopics(1))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.threads.length === 0) {
          Row().width('100%').height(44 + this.statusBarHeight)
          Column() {
            Image($r('app.media.icon_chat_bubble')).width(40).height(40).fillColor(AppColors.textTertiary).opacity(0.4).margin({ bottom: 8 })
            Text('暂无主题').fontSize(15).fontColor(AppColors.textTertiary)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ scroller: this.scroller }) {
            ListItem() {
              if (this.showSort) {
                Column() {
                  Row().width('100%').height(44 + this.statusBarHeight)
                  Row() {
                    ForEach(SORT_MODES, (mode: SortMode) => {
                      Text(mode.label)
                        .fontSize(13)
                        .fontColor(this.sortMode === mode.key ? AppColors.textPrimary : AppColors.textTertiary)
                        .fontWeight(this.sortMode === mode.key ? FontWeight.Bold : FontWeight.Normal)
                        .backgroundColor(this.sortMode === mode.key ? AppColors.bg : Color.Transparent)
                        .borderRadius(7)
                        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                        .layoutWeight(1)
                        .textAlign(TextAlign.Center)
                        .onClick(() => {
                          if (this.sortMode !== mode.key) {
                            this.sortMode = mode.key
                            this.loadTopics(1)
                          }
                        })
                    })
                  }
                  .width('92%').margin({ top: 8, bottom: 4 }).padding(3)
                  .backgroundColor(AppColors.bgSecondary).borderRadius(10)
                }
              } else {
                Row().width('100%').height(44 + this.statusBarHeight)
              }
            }
            LazyForEach(this.threadsDataSource, (thread: object) => {
              ListItem() {
                this.TopicCard(thread as Record<string, Object>)
              }
            }, (thread: object) => {
              const t = thread as Record<string, Object>
              return String(t['tid'] ?? '')
            })
            ListItem() {
              Row() {
                if (this.isLoadingMore) {
                  LoadingProgress().width(16).height(16).color(AppColors.textTertiary)
                  Text('加载更多...').fontSize(13).fontColor(AppColors.textTertiary).margin({ left: 8 })
                } else if (this.currentPage >= this.totalPages) {
                  Text('— 已到底 —').fontSize(12).fontColor(AppColors.textTertiary)
                }
              }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 16, bottom: 16 })
            }
          }
          .width('100%').layoutWeight(1)
          .scrollBar(BarState.Off)
          .divider({ strokeWidth: 0.5, color: AppColors.separator })
          .lanes(new BreakpointType(1, 1, 1).getValue(this.currentBreakpoint), 12)
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => {
            if (this.isLoadingMore || this.currentPage >= this.totalPages) return
            if (this.prefetchedThreads.length > 0 && this.prefetchedPage === this.currentPage + 1) {
              this.mergeThreads(this.prefetchedThreads)
              this.currentPage = this.prefetchedPage
              this.clearPrefetch()
              this.triggerPrefetch()
            } else {
              this.loadTopics(this.currentPage + 1)
            }
          })
        }
      }
      .width('100%').height('100%')

      PanelNavBar({
        title: this.boardName,
        showBack: this.showBack,
        rightIcon: $r('app.media.icon_bell'),
        rightIconBadge: this.unreadNotiCount,
        onRightClick: (): void => {
          routerStore.navigateActivity(Screen.notifications())
        }
      })
        .width('100%').position({ x: 0, y: 0 })

      Row() {
        Stack() {
          Image($r('app.media.icon_refresh'))
            .width(20).height(20)
            .fillColor(AppColors.primary)
        }
        .width(40).height(40).borderRadius(20)
        .backgroundColor(Color.Transparent)
        .shadow({ radius: 16, color: AppColors.shadow, offsetY: 4 })
        .backgroundEffect({
          radius: 10,
          saturation: 1.15,
          brightness: 1.08,
          color: AppColors.frostGlass
        })
        .onClick(() => this.loadTopics(1))
      }.width('100%').justifyContent(this.holdingStatus === HoldingHandStatus.LEFT_HAND_HELD ? FlexAlign.Start : FlexAlign.End)
      .padding({ left: this.holdingStatus === HoldingHandStatus.LEFT_HAND_HELD ? 16 : 0, right: this.holdingStatus === HoldingHandStatus.LEFT_HAND_HELD ? 0 : 16, bottom: 16 + this.navBarHeight })
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg).alignContent(Alignment.BottomEnd)
  }

  @Builder
  TopicCard(thread: Record<string, Object>) {
    Column() {
      Row() {
        Text(this.getTypeTags(Number(thread['type'] ?? 0)))
          .fontSize(15).fontColor(AppColors.textTertiary)
        Text(unescapeHtml(String(thread['subject'] ?? '')))
          .fontSize(15).lineHeight(22)
          .fontColor(this.getSubjectFontColor(String(thread['titleFont'] ?? '')))
          .fontWeight(this.isSubjectBold(String(thread['titleFont'] ?? '')) ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(this.isSubjectItalic(String(thread['titleFont'] ?? '')) ? FontStyle.Italic : FontStyle.Normal)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (this.isFavorites) {
          Text('✕').fontSize(16).fontColor(AppColors.textTertiary)
            .padding({ left: 8, right: 4 })
            .onClick(() => { this.handleRemoveFav(Number(thread['tid'] ?? 0)) })
        }
      }.width('100%').alignItems(VerticalAlign.Top)

      if (thread['previewSnippet']) {
        Text(unescapeHtml(String(thread['previewSnippet'] ?? '')))
          .fontSize(13).fontColor(AppColors.textSecondary).maxLines(2).lineHeight(19)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 10 }).width('100%')
      }

      Row() {
        Row() {
          AnonymousName({ author: String(thread['author'] ?? ''), isAnonymous: thread['isAnonymity'] as boolean, fontSize: 12 })
          if (appStore.getNote(String(thread['authorId'] ?? '')).length > 0) {
            Text('(' + appStore.getNote(String(thread['authorId'] ?? '')) + ')')
              .fontSize(11).fontColor(AppColors.warning).margin({ left: 3 })
          }
          Text(` · ${formatTime(Number(thread['postDate'] ?? 0))}`)
            .fontSize(12).fontColor(AppColors.textTertiary)
        }
        Row() { Image($r('app.media.icon_chat_bubble')).width(12).height(12).fillColor(AppColors.textTertiary); Text(` ${thread['replies'] ?? 0}`).fontSize(12).fontColor(AppColors.textTertiary) }
      }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 12 })
    }
    .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 }).alignItems(HorizontalAlign.Start)
    .onClick(() => {
      const tid = String(thread['tid'] ?? '')
      if (tid) {
        routerStore.navigateActivity(Screen.thread(tid))
      }
    })
  }
}
