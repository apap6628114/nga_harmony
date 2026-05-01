import { display, componentUtils } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { browseHistoryStore, BrowseHistoryEntry } from '../store/BrowseHistoryStore'
import { getThread, addFavorite, removeFavorite, votePost, ThreadResult, PostInfo, PostReplyResult, VoteResult } from '../service/NgaApi'
import { AppColors } from '../common/Constants'
import { PanelNavBar } from '../common/PanelNavBar'
import { PostItem } from '../common/PostItem'
import { PostInfoDataSource } from '../common/LazyDataSource'
import { floatingLayerStore, FloatingPage } from '../store/FloatingLayerStore'
import { voteRecordStore } from '../store/VoteRecordStore'
import { replyManager, ReplyType } from '../common/ReplyManager'
import { unescapeHtml } from '../common/Utils'
import type { ThreadInfo } from '../model/Thread'

@Component
export struct ThreadPanel {
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
  private indexToPage: number[] = []
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
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0
  @State showMoreMenu: boolean = false
  private scroller: Scroller = new Scroller()
  private loadedLouSet: Set<number> = new Set()
  private pageSwitchPending: boolean = false

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

  aboutToAppear(): void {
    this.loadPage(1)
    this.loadPersistedVotes()
  }

  private onThreadChanged(): void {
    this.allPosts = []
    this.postsDataSource.clear()
    this.currentPage = 1
    this.displayPage = 1
    this.indexToPage = []
    this.loadedPageStart = 1
    this.totalPages = 0
    this.hasError = false
    this.authorOnly = false
    this.favDone = false
    this.votedUpPids = new Set()
    this.votedDownPids = new Set()
    this.loadPage(1)
    this.loadPersistedVotes()
  }

  private async loadPersistedVotes(): Promise<void> {
    if (!appStore.auth.isAuthenticated) return
    const result = await voteRecordStore.load(appStore.auth.uid, this.threadTid)
    this.votedUpPids = result[0]
    this.votedDownPids = result[1]
  }

  private onScrollToPid(): void {
    if (this.threadPid.length > 0 && this.allPosts.length > 0) {
      const pidNum = parseInt(this.threadPid, 10)
      for (let i = 0; i < this.allPosts.length; i++) {
        if (this.allPosts[i].pid === pidNum) {
          this.scroller.scrollToIndex(i + 1, true, ScrollAlign.CENTER)
          break
        }
      }
    }
  }

  private async loadPage(page: number, replace?: boolean): Promise<void> {
    const replaceMode: boolean = replace === true || page === 1
    if (replaceMode) {
      this.allPosts = []
      this.postsDataSource.clear()
      this.loadedLouSet.clear()
      this.indexToPage = []
      this.isLoading = true
      this.hasError = false
      this.loadedPageStart = page
      if (replace === true && page > 1) {
        this.pageSwitchPending = true
      }
      this.scroller.scrollToIndex(1)
    } else {
      this.isLoadingMore = true
    }

    try {
      const result: ThreadResult = await getThread(appStore.auth.token, this.threadTid, '', this.authorOnly ? this.threadAuthorId : '', String(page))
      if (result.ok) {
        if (result.pagination) {
          this.totalPages = result.pagination.totalPages
        }
        this.currentPage = page
        if (result.threadInfo) {
          const info: ThreadInfo = result.threadInfo
          this.threadSubject = unescapeHtml(info.subject) || '帖子'
          this.threadFid = info.fid
          this.threadAuthorId = String(info.authorid)
        }
        if (replaceMode && appStore.auth.isAuthenticated) {
          this.recordBrowseHistory(result)
        }
        if (replaceMode) {
          for (let i = 0; i < result.posts.length; i++) {
            this.loadedLouSet.add(result.posts[i].lou)
          }
          this.allPosts = result.posts
          this.postsDataSource.replaceAll(result.posts)
          this.indexToPage = result.posts.map(() => page)
        } else {
          let newLouCount: number = 0
          for (let i = 0; i < result.posts.length; i++) {
            if (!this.loadedLouSet.has(result.posts[i].lou)) {
              newLouCount++
            }
            this.loadedLouSet.add(result.posts[i].lou)
          }
          if (newLouCount === 0) {
            this.totalPages = this.currentPage
          }
          const arr: PostInfo[] = []
          for (let i = 0; i < this.allPosts.length; i++) arr.push(this.allPosts[i])
          for (let i = 0; i < result.posts.length; i++) arr.push(result.posts[i])
          this.allPosts = arr
          this.postsDataSource.appendAll(result.posts)
          this.indexToPage.push(...result.posts.map(() => page))
        }
        if (replaceMode && this.threadPid.length > 0) {
          this.onScrollToPid()
        }
      } else if (page === 1) {
        this.hasError = true
        this.errorMsg = result.error || '加载失败'
        this.allPosts = []
        this.postsDataSource.clear()
      }
    } catch (e) {
      if (page === 1) {
        this.hasError = true
        this.errorMsg = (e as Error).message || '加载失败'
        this.allPosts = []
        this.postsDataSource.clear()
      }
    }
    this.isLoading = false
    this.isLoadingMore = false
    if (this.pageSwitchPending) {
      setTimeout((): void => {
        if (this.allPosts.length > 0) {
          this.scroller.scrollToIndex(1)
        }
        this.pageSwitchPending = false
      }, 80)
    }
  }

  private async loadPreviousPage(page: number): Promise<void> {
    this.isLoadingPrevious = true
    try {
      const result: ThreadResult = await getThread(appStore.auth.token, this.threadTid, '', this.authorOnly ? this.threadAuthorId : '', String(page))
      if (result.ok && result.posts.length > 0) {
        const prependCount: number = result.posts.length
        this.loadedPageStart = page
        this.allPosts = [...result.posts, ...this.allPosts]
        this.indexToPage = [...result.posts.map(() => page), ...this.indexToPage]
        this.postsDataSource.prependAll(result.posts)
        this.scroller.scrollToIndex(prependCount + 1)
      }
    } catch (e) {
    }
    this.isLoadingPrevious = false
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
          this.allPosts = []
          this.loadPage(1)
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
    const pidKey = String(post.pid)
    const wasUp: boolean = this.votedUpPids.has(pidKey)
    const wasDown: boolean = this.votedDownPids.has(pidKey)
    const result: VoteResult = await votePost(appStore.auth.token, Number(this.threadTid), post.pid, value)
    if (result.ok) {
      const msg = result.message
      const upPids = new Set(this.votedUpPids)
      const downPids = new Set(this.votedDownPids)
      if (msg.indexOf('取消了对这个帖子的支持') >= 0) {
        upPids.delete(pidKey)
      } else if (msg.indexOf('取消了对这个帖子的反对') >= 0) {
        downPids.delete(pidKey)
      } else if (msg.indexOf('表示支持') >= 0) {
        upPids.add(pidKey)
        downPids.delete(pidKey)
      } else if (msg.indexOf('表示反对') >= 0) {
        downPids.add(pidKey)
        upPids.delete(pidKey)
      }
      this.votedUpPids = upPids
      this.votedDownPids = downPids
      voteRecordStore.save(appStore.auth.uid, this.threadTid, upPids, downPids)
      const isUp: boolean = upPids.has(pidKey)
      const isDown: boolean = downPids.has(pidKey)
      this.applyVoteToPost(post, (isUp ? 1 : 0) - (wasUp ? 1 : 0), (isDown ? 1 : 0) - (wasDown ? 1 : 0))
      if (msg.length > 0) {
        appStore.showToast(msg)
      }
    } else {
      appStore.showToast(result.error || '操作失败')
    }
  }

  private applyVoteToPost(post: PostInfo, scoreDelta: number, score2Delta: number): void {
    if (scoreDelta === 0 && score2Delta === 0) return
    for (let i = 0; i < this.allPosts.length; i++) {
      if (this.allPosts[i].pid === post.pid) {
        this.allPosts[i].score += scoreDelta
        this.allPosts[i].score_2 += score2Delta
        this.postsDataSource.updateAt(i, this.allPosts[i])
        break
      }
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
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding({ top: 44 + this.statusBarHeight })
      } else if (this.hasError) {
        Column() {
          Text(this.errorMsg).fontSize(14).fontColor(AppColors.textTertiary).margin({ bottom: 12 })
          Button('重试').fontSize(14).fontColor(AppColors.primary).backgroundColor(AppColors.bgSecondary).borderRadius(10)
            .onClick(() => this.loadPage(1))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding({ top: 44 + this.statusBarHeight })
      } else {
        List({ scroller: this.scroller }) {
          ListItem() {
            Row().width('100%').height(44 + this.statusBarHeight)
          }
          LazyForEach(this.postsDataSource, (post: PostInfo) => {
            ListItem() {
              PostItem({
                post: post,
                votedUpPids: this.votedUpPids,
                votedDownPids: this.votedDownPids,
                onImageClick: (urls: string[], index: number): void => {
                  this.openImageViewer(urls, index)
                },
                onLinkClick: (href: string): void => {
                  this.handleLinkClick(href)
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
                  floatingLayerStore.replyOnSend = (text: string, isAnony: boolean): Promise<void> => { return this.handleReplySend(text, isAnony) }
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
                } else if (this.currentPage >= this.totalPages && this.allPosts.length > 0) {
                  Text('已加载全部回复').fontSize(13).fontColor(AppColors.textTertiary)
                }
              }.width('100%').justifyContent(FlexAlign.Center)
            }.width('100%').height(44).justifyContent(FlexAlign.Center)
          }
        }
        .width('100%').layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
        .edgeEffect(EdgeEffect.Spring)
        .maintainVisibleContentPosition(true)
        .onScrollIndex((start: number, end: number, center: number): void => {
          const dataIndex = center - 1
          if (dataIndex >= 0 && dataIndex < this.indexToPage.length) {
            this.displayPage = this.indexToPage[dataIndex]
          }
        })
        .onReachEnd(() => {
          if (!this.isLoadingMore && this.currentPage < this.totalPages) {
            this.loadPage(this.currentPage + 1)
          }
        })
        .onReachStart(() => {
          if (!this.isLoadingPrevious && this.loadedPageStart > 1 && !this.pageSwitchPending) {
            this.loadPreviousPage(this.loadedPageStart - 1)
          }
        })
      }
    }
    .width('100%').height('100%')

      // 标题栏毛玻璃覆盖层
      PanelNavBar({ title: this.threadSubject, rightIcon: $r('app.media.icon_more'), onRightClick: (): void => { this.showMoreMenu = !this.showMoreMenu } })
        .width('100%').position({ x: 0, y: 0 })

      // 底部工具栏：页数选择器（左）+ 回复按钮（右）
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
              }.width(24).height(28).onClick(() => this.loadPage(1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text('2').fontSize(14).fontColor(this.displayPage === 2 ? AppColors.primary : AppColors.textSecondary)
                  .fontWeight(this.displayPage === 2 ? FontWeight.Bold : FontWeight.Regular)
                if (this.displayPage === 2) {
                  Text('•').fontSize(10).fontColor(AppColors.primary)
                    .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
                }
              }.width(24).height(28).onClick(() => this.loadPage(2, true))
            } else if (this.displayPage === 1) {
              Stack() {
                Text('1').fontSize(14).fontColor(AppColors.primary).fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPage(1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text('2').fontSize(14).fontColor(AppColors.textSecondary).fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(2, true))
            } else if (this.displayPage === this.totalPages) {
              Stack() {
                Text(String(this.totalPages - 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(this.totalPages - 1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.totalPages)).fontSize(14).fontColor(AppColors.primary)
                  .fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPage(this.totalPages, true))
            } else {
              Stack() {
                Text(String(this.displayPage - 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(this.displayPage - 1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.displayPage)).fontSize(14).fontColor(AppColors.primary)
                  .fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPage(this.displayPage, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.displayPage + 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(this.displayPage + 1, true))
            }
            Divider().vertical(true).height(16).color(AppColors.dividerStrong)
            Text('到').fontSize(13).fontColor(AppColors.primary).padding({ left: 4, right: 2 })
              .onClick(() => {
                floatingLayerStore.pagePickerTotalPages = this.totalPages
                floatingLayerStore.pagePickerCurrentPage = this.displayPage
                try {
                  const ctx = this.getUIContext()
                  const info = componentUtils.getRectangleById('threadPanelRoot')
                  const panelLeftVp = ctx.px2vp(info.windowOffset.x)
                  const panelTopVp = ctx.px2vp(info.windowOffset.y)
                  const panelHeightVp = ctx.px2vp(info.size.height)
                  const dInfo = display.getDefaultDisplaySync()
                  const screenW = ctx.px2vp(dInfo.width)
                  const screenH = ctx.px2vp(dInfo.height)
                  const pickerW = 220
                  const pickerH = 180
                  let px = panelLeftVp + 16
                  let py = panelTopVp + panelHeightVp - 244 - this.navBarHeight
                  px = Math.max(8, Math.min(px, screenW - pickerW - 8))
                  py = Math.max(8, Math.min(py, screenH - pickerH - 8))
                  floatingLayerStore.pagePickerX = px
                  floatingLayerStore.pagePickerY = py
                } catch (e) {
                  floatingLayerStore.pagePickerX = 16
                  floatingLayerStore.pagePickerY = 400
                }
                floatingLayerStore.pagePickerOnSelect = (page: number): void => {
                  if (page !== this.displayPage) {
                    this.loadPage(page, true)
                  }
                }
                floatingLayerStore.push(FloatingPage.PAGE_PICKER)
              })
          }
          .padding({ left: 8, right: 8, top: 0, bottom: 0 })
          .height(40).alignItems(VerticalAlign.Center)
          .backgroundColor('rgba(255, 255, 255, 0.0)').borderRadius(20)
          .shadow({ radius: 16, color: AppColors.shadow, offsetY: 4 })
          .backgroundEffect({
            radius: 10,
            saturation: 1.15,
            brightness: 1.08,
            color: 'rgba(255, 255, 255, 0.25)'
          })
        }

        Blank().layoutWeight(1)

        Stack() {
          Image($r('app.media.icon_reply'))
            .width(20).height(20)
            .fillColor(AppColors.primary)
        }
        .width(40).height(40).borderRadius(20)
        .backgroundColor('rgba(255, 255, 255, 0.0)')
        .shadow({ radius: 16, color: AppColors.shadow, offsetY: 4 })
        .backgroundEffect({
          radius: 10,
          saturation: 1.15,
          brightness: 1.08,
          color: 'rgba(255, 255, 255, 0.25)'
        })
        .onClick(() => {
          replyManager.startThreadReply(Number(this.threadTid), this.threadFid)
          floatingLayerStore.replyDialogTitle = replyManager.dialogTitle
          floatingLayerStore.replyOnSend = (text: string, isAnony: boolean): Promise<void> => { return this.handleReplySend(text, isAnony) }
          floatingLayerStore.push(FloatingPage.REPLY_DIALOG)
        })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 + this.navBarHeight }).alignItems(VerticalAlign.Center)

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
                  this.loadPage(1, true)
                })
            }
            .width('100%')
          }
          .width(150)
          .backgroundColor(AppColors.white)
          .borderRadius(10)
          .shadow({ radius: 16, color: AppColors.shadowLight, offsetY: 4 })
          .position({ top: this.statusBarHeight + 44 + 6, right: 16 })
        }
        .width('100%').height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }

    }
    .width('100%').height('100%').backgroundColor(AppColors.bg).alignContent(Alignment.BottomEnd)
    .id('threadPanelRoot')
  }
}
