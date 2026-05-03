import { display } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { ngaClient } from '../service/NgaClient'
import { browseHistoryStore, BrowseHistoryEntry } from '../store/BrowseHistoryStore'
import { getThread, addFavorite, removeFavorite, votePost, ThreadResult, PostInfo, PostReplyResult, VoteResult } from '../service/NgaApi'
import { preWarmBBCache } from '../service/BBCodeCache'
import { AppColors } from '../common/Constants'
import { PanelNavBar } from '../common/PanelNavBar'
import { PostItem } from '../common/PostItem'
import { PostInfoDataSource } from '../common/LazyDataSource'
import { floatingLayerStore, FloatingPage } from '../store/FloatingLayerStore'
import { voteRecordStore } from '../store/VoteRecordStore'
import { replyManager, ReplyType } from '../common/ReplyManager'
import { unescapeHtml } from '../common/Utils'
import { ThreadPaginationManager } from '../common/ThreadPaginationManager'
import type { ThreadInfo } from '../model/Thread'

enum HoldingHandStatus {
  NOT_HELD = 0,
  LEFT_HAND_HELD = 1,
  RIGHT_HAND_HELD = 2,
  BOTH_HANDS_HELD = 3,
  UNKNOWN_STATUS = 16
}

const LOAD_REPLACE: string = 'replace'
const LOAD_APPEND: string = 'append'
const LOAD_PREPEND: string = 'prepend'
const NAV_BAR_H: number = 44
const PAGE_SCROLL_DELAY: number = 80

@Component
export struct ThreadPanel {
  @State holdingStatus: HoldingHandStatus = appStore.settings.holdingHand as HoldingHandStatus
  @State holdingDetected: boolean = false

  @Prop @Watch('onThreadChanged') threadTid: string = ''
  @Prop threadPid: string = ''
  @Prop @Watch('onScrollToPid') navEntryId: number = 0
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State errorMsg: string = ''
  @State allPosts: PostInfo[] = []
  private postsDataSource: PostInfoDataSource = new PostInfoDataSource()
  @State currentPage: number = 1
  @State displayPage: number = 1
  @State loadedPageStart: number = 1
  @State totalPages: number = 0
  @State isLoadingMore: boolean = false
  @State isLoadingPrevious: boolean = false
  @State authorOnly: boolean = false
  @State favDone: boolean = false
  @State threadSubject: string = '帖子'
  @State threadFid: number = 0
  @State threadAuthorId: string = ''
  @State votedUpPids: Set<string> = new Set()
  @State votedDownPids: Set<string> = new Set()
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0
  @State showMoreMenu: boolean = false
  @State showPagePicker: boolean = false
  private pagePickerTotalPages: number = 0
  private pagePickerCurrentPage: number = 0
  private pagePickerOnSelect: ((page: number) => void) | null = null
  private scroller: Scroller = new Scroller()
  private pageSwitchPending: boolean = false
  private mgr: ThreadPaginationManager = new ThreadPaginationManager()

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

  private showProfileCard(uid: string, screenX: number, screenY: number): void {
    const cardW: number = 280
    const cardH: number = 400
    const pad: number = 8
    let posX: number = screenX
    let posY: number = screenY
    try {
      const context = this.getUIContext()
      const displayInfo = display.getDefaultDisplaySync()
      const screenW = context.px2vp(displayInfo.width)
      const screenH = context.px2vp(displayInfo.height)
      posX = Math.max(pad, Math.min(screenX - cardW / 2, screenW - cardW - pad))
      posY = Math.max(pad, Math.min(screenY + pad, screenH - cardH - pad))
    } catch (e) {
      posX = screenX - cardW / 2
      posY = screenY + pad
    }
    floatingLayerStore.profileCardUid = uid
    floatingLayerStore.profileCardX = posX
    floatingLayerStore.profileCardY = posY
    floatingLayerStore.push(FloatingPage.PROFILE_CARD)
  }

  private hasInitiallyLoaded: boolean = false

  aboutToAppear(): void {
    this.hasInitiallyLoaded = true
    if (this.threadTid) {
      this.loadPosts(1, LOAD_REPLACE)
    }
    this.loadPersistedVotes()
    this.startHoldingHandMonitoring()
  }

  aboutToDisappear(): void {
    this.stopHoldingHandMonitoring()
  }

  private onThreadChanged(): void {
    if (!this.hasInitiallyLoaded) {
      this.hasInitiallyLoaded = true
      return
    }
    this.mgr.reset()
    this.allPosts = []
    this.postsDataSource.clear()
    this.currentPage = 1
    this.displayPage = 1
    this.loadedPageStart = 1
    this.totalPages = 0
    this.isLoading = true
    this.isLoadingMore = false
    this.isLoadingPrevious = false
    this.hasError = false
    this.authorOnly = false
    this.favDone = false
    this.votedUpPids = new Set()
    this.votedDownPids = new Set()
    this.pageSwitchPending = false
    this.loadPosts(1, LOAD_REPLACE)
    this.loadPersistedVotes()
  }

  private async loadPersistedVotes(): Promise<void> {
    if (!appStore.auth.isAuthenticated) return
    const result = await voteRecordStore.load(appStore.auth.uid, this.threadTid)
    this.votedUpPids = result[0]
    this.votedDownPids = result[1]
  }

  private onScrollToPid(): void {
    if (this.threadPid.length > 0 && this.mgr.posts.length > 0) {
      const pidNum: number = parseInt(this.threadPid, 10)
      const idx: number = this.mgr.findPostIndex(pidNum)
      if (idx >= 0) {
        this.scroller.scrollToIndex(idx + 1, true, ScrollAlign.CENTER)
      }
    }
  }

  private preWarmPosts(posts: PostInfo[]): void {
    for (let i: number = 0; i < posts.length; i++) {
      const p: PostInfo = posts[i]
      preWarmBBCache(p.content)
      if (p.signature) preWarmBBCache(p.signature)
      const comments: PostInfo[] = p.comments
      for (let j: number = 0; j < comments.length; j++) {
        preWarmBBCache(comments[j].content)
      }
    }
  }

  private buildPageArray(): number[] {
    const arr: number[] = []
    for (let i: number = 1; i <= this.pagePickerTotalPages; i++) {
      arr.push(i)
    }
    return arr
  }

  private async loadPosts(targetPage: number, mode: string): Promise<void> {
    const gen: number = this.mgr.nextGeneration()

    if (mode === LOAD_REPLACE) {
      this.mgr.reset()
      this.allPosts = []
      this.postsDataSource.clear()
      this.isLoading = true
      this.isLoadingMore = false
      this.isLoadingPrevious = false
      this.hasError = false
      this.loadedPageStart = targetPage
      if (targetPage > 1) {
        this.pageSwitchPending = true
      }
      this.scroller.scrollToIndex(1)
    } else if (mode === LOAD_APPEND) {
      this.isLoadingMore = true
    } else {
      this.isLoadingPrevious = true
    }

    try {
      const noteMap: Record<string, string> = appStore.getNoteMap()
      const result: ThreadResult = await getThread(
        appStore.auth.token, this.threadTid, '',
        this.authorOnly ? this.threadAuthorId : '', String(targetPage),
        appStore.getBlacklistIds(), appStore.getEnabledKeywords(),
        noteMap
      )

      if (gen !== this.mgr.getGeneration()) return

      if (result.ok) {
        this.preWarmPosts(result.posts)

        if (result.pagination) {
          this.totalPages = result.pagination.totalPages
        }
        if (result.threadInfo) {
          const info: ThreadInfo = result.threadInfo
          this.threadSubject = unescapeHtml(info.subject) || '帖子'
          this.threadFid = info.fid
          this.threadAuthorId = String(info.authorid)
        }

        if (mode === LOAD_REPLACE) {
          this.mgr.replaceWith(result.posts, targetPage, this.totalPages)
          this.allPosts = result.posts
          this.postsDataSource.replaceAll(result.posts)
          if (appStore.auth.isAuthenticated) {
            this.recordBrowseHistory(result)
          }
          if (this.threadPid.length > 0) {
            this.onScrollToPid()
          }
        } else if (mode === LOAD_APPEND) {
          const added: PostInfo[] = this.mgr.appendPosts(result.posts, targetPage, this.totalPages)
          if (added.length > 0) {
            this.allPosts = this.mgr.posts
            this.postsDataSource.appendAll(added)
          }
        } else {
          const added: PostInfo[] = this.mgr.prependPosts(result.posts, targetPage)
          if (added.length > 0) {
            this.allPosts = this.mgr.posts
            this.postsDataSource.prependAll(added)
            this.scroller.scrollToIndex(added.length + 1)
          }
        }
        this.syncManagerState()
      } else if (mode === LOAD_REPLACE) {
        this.hasError = true
        this.errorMsg = result.error || '加载失败'
        this.allPosts = []
        this.postsDataSource.clear()
      }
    } catch (e) {
      if (gen !== this.mgr.getGeneration()) return
      if (mode === LOAD_REPLACE) {
        this.hasError = true
        this.errorMsg = (e as Error).message || '加载失败'
        this.allPosts = []
        this.postsDataSource.clear()
      } else {
        console.error('loadPosts failed: ' + (e as Error).message)
      }
    }

    this.isLoading = false
    this.isLoadingMore = false
    this.isLoadingPrevious = false

    if (this.pageSwitchPending) {
      setTimeout((): void => {
        if (this.mgr.posts.length > 0) {
          this.scroller.scrollToIndex(1)
        }
        this.pageSwitchPending = false
      }, PAGE_SCROLL_DELAY)
    }
  }

  private syncManagerState(): void {
    this.currentPage = this.mgr.currentPage
    this.totalPages = this.mgr.totalPages
    this.loadedPageStart = this.mgr.loadedPageStart
  }

  private recordBrowseHistory(result: ThreadResult): void {
    const entry = new BrowseHistoryEntry()
    entry.tid = this.threadTid
    entry.board = result.forumName
    if (result.threadInfo) {
      const info: ThreadInfo = result.threadInfo
      entry.subject = info.subject
      entry.author = info.author
      entry.authorid = String(info.authorid)
      entry.replies = info.replies
    } else if (result.posts.length > 0) {
      const firstPost = result.posts[0]
      entry.subject = firstPost.subject
      entry.author = firstPost.author
      entry.authorid = String(firstPost.authorid)
    }
    if (entry.subject.length === 0) {
      return
    }
    browseHistoryStore.add(appStore.auth.uid, entry)
  }

  private async handleReplySend(text: string, isAnony: boolean): Promise<void> {
    try {
      const result: PostReplyResult = await replyManager.send(text, isAnony)
      if (result.ok) {
        const isComment: boolean = replyManager.type === ReplyType.COMMENT
        appStore.showToast(isComment ? '贴条成功' : '回复成功')
        if (this.currentPage >= this.totalPages) {
          await this.loadPosts(1, LOAD_REPLACE)
        }
      } else {
        appStore.showToast(result.error || '操作失败')
      }
    } catch (e) {
      appStore.showToast((e as Error).message || '操作失败')
    }
  }

  private async handleFavorite(): Promise<void> {
    if (this.favDone || !this.threadTid) return
    try {
      const result = await addFavorite(appStore.auth.token, Number(this.threadTid), 0)
      if (result.ok) {
        this.favDone = true
        appStore.showToast('收藏成功')
      } else {
        appStore.showToast(result.error || '收藏失败')
      }
    } catch (e) {
      appStore.showToast('收藏失败')
    }
  }

  private async handleUnfavorite(): Promise<void> {
    if (!this.favDone || !this.threadTid) return
    try {
      const result = await removeFavorite(appStore.auth.token, Number(this.threadTid), 0, 1)
      if (result.ok) {
        this.favDone = false
        appStore.showToast('已取消收藏')
      } else {
        appStore.showToast(result.error || '取消收藏失败')
      }
    } catch (e) {
      appStore.showToast('取消收藏失败')
    }
  }

  private async handleVote(post: PostInfo, value: number): Promise<void> {
    if (!appStore.auth.isAuthenticated) {
      appStore.showToast('请先登录')
      return
    }
    const pidKey: string = String(post.pid)
    const wasUp: boolean = this.votedUpPids.has(pidKey)
    const wasDown: boolean = this.votedDownPids.has(pidKey)
    const result: VoteResult = await votePost(appStore.auth.token, Number(this.threadTid), post.pid, value)
    if (result.ok) {
      const upPids = new Set(this.votedUpPids)
      const downPids = new Set(this.votedDownPids)
      if (result.message.indexOf('取消了对这个帖子的支持') >= 0) {
        upPids.delete(pidKey)
      } else if (result.message.indexOf('取消了对这个帖子的反对') >= 0) {
        downPids.delete(pidKey)
      } else if (result.message.indexOf('表示支持') >= 0) {
        upPids.add(pidKey)
        downPids.delete(pidKey)
      } else if (result.message.indexOf('表示反对') >= 0) {
        downPids.add(pidKey)
        upPids.delete(pidKey)
      }
      this.votedUpPids = upPids
      this.votedDownPids = downPids
      voteRecordStore.save(appStore.auth.uid, this.threadTid, upPids, downPids)
      const isUp: boolean = upPids.has(pidKey)
      const isDown: boolean = downPids.has(pidKey)
      const scoreDelta: number = (isUp ? 1 : 0) - (wasUp ? 1 : 0)
      const score2Delta: number = (isDown ? 1 : 0) - (wasDown ? 1 : 0)
      const voteIdx: number = this.mgr.updateVoteScore(post.pid, scoreDelta, score2Delta)
      if (voteIdx >= 0) {
        this.postsDataSource.updateAt(voteIdx, this.mgr.posts[voteIdx])
      }
      if (result.message.length > 0) {
        appStore.showToast(result.message)
      }
    } else {
      appStore.showToast(result.error || '操作失败')
    }
  }

  private openImageViewer(urls: string[], index: number): void {
    floatingLayerStore.imageViewerUrls = urls
    floatingLayerStore.imageViewerIndex = index
    floatingLayerStore.push(FloatingPage.IMAGE_VIEWER)
  }

  private handleLinkClick(href: string): void {
    if (href.startsWith('#/thread?')) {
      const params = new Map<string, string>()
      const query = href.substring(href.indexOf('?') + 1)
      const parts = query.split('&')
      for (let i = 0; i < parts.length; i++) {
        const kv = parts[i].split('=')
        if (kv.length === 2) params.set(kv[0], kv[1])
      }
      const tid = params.get('tid') || ''
      const pageStr = params.get('page') || '1'
      const pid = params.get('pid') || ''
      const page = parseInt(pageStr, 10) || 1
      if (tid.length > 0) {
        routerStore.navigateActivity(Screen.thread(tid, page, pid))
      }
    } else if (href.startsWith('#/profile?')) {
      const uidStr = href.split('uid=')[1]
      if (uidStr) {
        this.showProfileCard(uidStr.split('&')[0], 200, 200)
      }
    } else if (href.startsWith('http://') || href.startsWith('https://')) {
      try {
        const ctx = getContext(this) as common.UIAbilityContext
        ctx.openLink(href)
      } catch (e) {}
    }
  }

  build() {
    Stack() {
      Column() {

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(28).height(28).color(AppColors.textTertiary)
          Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 8 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .padding({ top: NAV_BAR_H + this.statusBarHeight })
      } else if (this.hasError) {
        Column() {
          Text(this.errorMsg).fontSize(14).fontColor(AppColors.textTertiary).margin({ bottom: 12 })
          Button('重试').fontSize(14).fontColor(AppColors.primary).backgroundColor(AppColors.bgSecondary).borderRadius(10)
            .onClick(() => this.loadPosts(1, LOAD_REPLACE))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .padding({ top: NAV_BAR_H + this.statusBarHeight })
      } else {
        List({ scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(NAV_BAR_H + this.statusBarHeight)
          }
          LazyForEach(this.postsDataSource, (post: PostInfo) => {
            ListItem() {
              PostItem({
                post: post,
                votedUpPids: this.votedUpPids,
                votedDownPids: this.votedDownPids,
                holdingHand: this.holdingStatus,
                onImageClick: (urls: string[], index: number): void => {
                  this.openImageViewer(urls, index)
                },
                onLinkClick: (href: string): void => {
                  this.handleLinkClick(href)
                },
                onVideoClick: (url: string): void => {
                  this.handleLinkClick(url)
                },
                onProfileClick: (uid: string, screenX: number, screenY: number): void => {
                  this.showProfileCard(uid, screenX, screenY)
                },
                onVote: (p: PostInfo, value: number): void => {
                  this.handleVote(p, value)
                },
                onReply: (p: PostInfo): void => {
                  replyManager.startFloorReply(p, Number(this.threadTid), this.threadFid, this.currentPage)
                  floatingLayerStore.replyDialogTitle = replyManager.dialogTitle
                  floatingLayerStore.replyOnSend = (text: string, isAnony: boolean): Promise<void> => {
                    return this.handleReplySend(text, isAnony)
                  }
                  floatingLayerStore.push(FloatingPage.REPLY_DIALOG)
                },
              })
            }
          }, (post: PostInfo) => String(post.pid))
          ListItem() {
            Column() {
              Row() {
                if (this.isLoadingMore) {
                  LoadingProgress().width(16).height(16).color(AppColors.textTertiary)
                  Text('加载更多...').fontSize(13).fontColor(AppColors.textTertiary).margin({ left: 8 })
                } else if (this.currentPage >= this.totalPages && this.mgr.posts.length > 0) {
                  Text('已加载全部回复').fontSize(13).fontColor(AppColors.textTertiary)
                }
              }.width('100%').justifyContent(FlexAlign.Center)
            }.width('100%').height(NAV_BAR_H).justifyContent(FlexAlign.Center)
          }
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
        .edgeEffect(EdgeEffect.Spring)
        .maintainVisibleContentPosition(true)
        .onScrollIndex((start: number, end: number, center: number): void => {
          this.displayPage = this.mgr.getDisplayPage(center - 1)
        })
        .onReachEnd(() => {
          if (!this.isLoadingMore && this.mgr.hasMore) {
            this.loadPosts(this.currentPage + 1, LOAD_APPEND)
          }
        })
        .onReachStart(() => {
          if (!this.isLoadingPrevious && this.loadedPageStart > 1 && !this.pageSwitchPending) {
            this.loadPosts(this.loadedPageStart - 1, LOAD_PREPEND)
          }
        })
      }
    }
    .width('100%').height('100%')

      PanelNavBar({
        title: this.threadSubject,
        rightIcon: $r('app.media.icon_more'),
        onRightClick: (): void => {
          this.showMoreMenu = !this.showMoreMenu
        }
      })
        .width('100%').position({ x: 0, y: 0 })

      Row() {
        if (this.totalPages > 1) {
          Row() {
            if (this.totalPages === 2) {
              Stack() {
                Text('1').fontSize(14).fontColor(this.displayPage === 1 ? AppColors.primary : AppColors.textSecondary)
                  .fontWeight(this.displayPage === 1 ? FontWeight.Bold : FontWeight.Regular)
                if (this.displayPage === 1) {
                  Text('•').fontSize(10).fontColor(AppColors.primary)
                    .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
                }
              }.width(24).height(28).onClick(() => this.loadPosts(1, LOAD_REPLACE))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text('2').fontSize(14).fontColor(this.displayPage === 2 ? AppColors.primary : AppColors.textSecondary)
                  .fontWeight(this.displayPage === 2 ? FontWeight.Bold : FontWeight.Regular)
                if (this.displayPage === 2) {
                  Text('•').fontSize(10).fontColor(AppColors.primary)
                    .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
                }
              }.width(24).height(28).onClick(() => this.loadPosts(2, LOAD_REPLACE))
            } else if (this.displayPage === 1) {
              Stack() {
                Text('1').fontSize(14).fontColor(AppColors.primary).fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPosts(1, LOAD_REPLACE))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text('2').fontSize(14).fontColor(AppColors.textSecondary).fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPosts(2, LOAD_REPLACE))
            } else if (this.displayPage === this.totalPages) {
              Stack() {
                Text(String(this.totalPages - 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPosts(this.totalPages - 1, LOAD_REPLACE))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.totalPages)).fontSize(14).fontColor(AppColors.primary)
                  .fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPosts(this.totalPages, LOAD_REPLACE))
            } else {
              Stack() {
                Text(String(this.displayPage - 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPosts(this.displayPage - 1, LOAD_REPLACE))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.displayPage)).fontSize(14).fontColor(AppColors.primary)
                  .fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPosts(this.displayPage, LOAD_REPLACE))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.displayPage + 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPosts(this.displayPage + 1, LOAD_REPLACE))
            }
            if (this.totalPages > 2) {
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Text('到').fontSize(13).fontColor(AppColors.primary).padding({ left: 4, right: 2 })
                .onClick(() => {
                  this.pagePickerCurrentPage = this.displayPage
                  this.pagePickerTotalPages = this.totalPages
                  this.pagePickerOnSelect = (page: number): void => {
                    if (page !== this.displayPage) {
                      this.loadPosts(page, LOAD_REPLACE)
                    }
                  }
                  this.showPagePicker = true
                })
            }
          }
          .padding({ left: 8, right: 8, top: 0, bottom: 0 })
          .height(40).alignItems(VerticalAlign.Center)
          .backgroundColor(Color.Transparent).borderRadius(20)
          .shadow({ radius: 16, color: AppColors.shadow, offsetY: 4 })
          .backgroundEffect({
            radius: 10,
            saturation: 1.15,
            brightness: 1.08,
            color: AppColors.frostGlass
          })
          .margin({ right: 8 })
        }

        Stack() {
          Image($r('app.media.icon_reply'))
            .width(20).height(20).fillColor(AppColors.primary)
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
        .onClick(() => {
          replyManager.startThreadReply(Number(this.threadTid), this.threadFid)
          floatingLayerStore.replyDialogTitle = replyManager.dialogTitle
          floatingLayerStore.replyOnSend = (text: string, isAnony: boolean): Promise<void> => {
            return this.handleReplySend(text, isAnony)
          }
          floatingLayerStore.push(FloatingPage.REPLY_DIALOG)
        })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 + this.navBarHeight }).alignItems(VerticalAlign.Center)
      .justifyContent(this.holdingStatus === HoldingHandStatus.LEFT_HAND_HELD ? FlexAlign.Start : FlexAlign.End)

      if (this.showMoreMenu) {
        Stack() {
          Column() {}.width('100%').height('100%').onClick(() => { this.showMoreMenu = false })

          Column() {
            Column() {
              Text(this.favDone ? '取消收藏' : '收藏帖子').fontSize(15)
                .fontColor(AppColors.textPrimary)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .width('100%')
                .onClick(() => {
                  if (this.favDone) {
                    this.handleUnfavorite()
                  } else {
                    this.handleFavorite()
                  }
                  this.showMoreMenu = false
                })
            }
            .width('100%')

            Divider().width('100%').color(AppColors.separator)

            Column() {
              Text('只看楼主').fontSize(15)
                .fontColor(this.authorOnly ? AppColors.primary : AppColors.textPrimary)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .width('100%')
                .onClick(() => {
                  this.authorOnly = !this.authorOnly
                  this.showMoreMenu = false
                  this.loadPosts(1, LOAD_REPLACE)
                })
            }
            .width('100%')

            Divider().width('100%').color(AppColors.separator)

            Column() {
              Text('从网页打开').fontSize(15)
                .fontColor(AppColors.textPrimary)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .width('100%')
                .onClick(() => {
                  this.showMoreMenu = false
                  const baseUrl: string = ngaClient.getActiveDomain()
                  const threadUrl: string = baseUrl + '/read.php?tid=' + this.threadTid
                  routerStore.navigateActivity(Screen.webview(threadUrl))
                })
            }
            .width('100%')
          }
          .width(150)
          .backgroundColor(AppColors.bgTertiary)
          .borderRadius(10)
          .shadow({ radius: 16, color: AppColors.shadowLight, offsetY: 4 })
          .position({ top: this.statusBarHeight + NAV_BAR_H + 6, right: 16 })
        }
        .width('100%').height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }

      if (this.showPagePicker) {
        Stack() {
          Column().width('100%').height('100%').onClick(() => { this.showPagePicker = false })
          Column() {
            Text('选择页面').fontSize(14).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Bold)
              .padding({ top: 12, bottom: 8 }).width('100%').textAlign(TextAlign.Center)
            Divider().color(AppColors.separator)
            Scroll() {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
                ForEach(this.buildPageArray(), (p: number) => {
                  Text(String(p)).fontSize(15)
                    .fontColor(p === this.pagePickerCurrentPage ? AppColors.primary : AppColors.textPrimary)
                    .fontWeight(p === this.pagePickerCurrentPage ? FontWeight.Bold : FontWeight.Regular)
                    .width(40).height(40).textAlign(TextAlign.Center).borderRadius(8)
                    .backgroundColor(p === this.pagePickerCurrentPage ? AppColors.primaryLight : Color.Transparent)
                    .onClick(() => {
                      if (this.pagePickerOnSelect) {
                        this.pagePickerOnSelect(p)
                      }
                      this.showPagePicker = false
                    })
                }, (p: number) => String(p))
              }.width('100%')
            }.width('100%').height(120).align(Alignment.TopStart)
          }
          .width(220).height(180).padding({ left: 10, right: 10 })
          .backgroundColor(AppColors.bgTertiary).borderRadius(12)
          .shadow({ radius: 16, color: AppColors.shadow, offsetY: 4 })
          .position(
            this.holdingStatus === HoldingHandStatus.LEFT_HAND_HELD
              ? { bottom: 64 + this.navBarHeight, left: 16 }
              : { bottom: 64 + this.navBarHeight, right: 16 }
          )
        }
        .width('100%').height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }

    }
    .width('100%').height('100%').backgroundColor(AppColors.bg).alignContent(Alignment.BottomEnd)
    .id('threadPanelRoot')
  }
}
