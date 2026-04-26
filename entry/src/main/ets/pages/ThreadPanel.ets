import { display } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { browseHistoryStore, BrowseHistoryEntry } from '../store/BrowseHistoryStore'
import { getThread, getPostAuth, postReply, postComment, addFavorite, votePost, ThreadResult, PostInfo, PostAuthResult, PostReplyResult, VoteResult } from '../service/NgaApi'
import { AppColors } from '../common/Constants'
import { PostItem } from '../common/PostItem'
import { PostInfoDataSource } from '../common/LazyDataSource'
import { floatingLayerStore, FloatingPage } from '../store/FloatingLayerStore'
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
  @State loadedPageStart: number = 1
  @State totalPages: number = 0
  @State isLoadingMore: boolean = false
  @State isLoadingPrevious: boolean = false
  @State authorOnly: boolean = false
  @State favDone: boolean = false
  @State threadSubject: string = '帖子'
  @State threadFid: number = 0
  @State threadAuthorId: string = ''
  @State showPagePicker: boolean = false
  @State votedUpPids: Set<string> = new Set()
  @State votedDownPids: Set<string> = new Set()
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0
  private scroller: Scroller = new Scroller()
  private replyTargetPid: number = 0
  private loadedLouSet: Set<number> = new Set()

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
  }

  private onThreadChanged(): void {
    this.allPosts = []
    this.postsDataSource.clear()
    this.currentPage = 1
    this.loadedPageStart = 1
    this.totalPages = 0
    this.hasError = false
    this.authorOnly = false
    this.favDone = false
    this.votedUpPids = new Set()
    this.votedDownPids = new Set()
    this.loadPage(1)
  }

  private onScrollToPid(): void {
    if (this.threadPid.length > 0 && this.allPosts.length > 0) {
      const pidNum = parseInt(this.threadPid, 10)
      for (let i = 0; i < this.allPosts.length; i++) {
        if (this.allPosts[i].pid === pidNum) {
          this.scroller.scrollToIndex(i, true, ScrollAlign.CENTER)
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
      this.isLoading = true
      this.hasError = false
      this.loadedPageStart = page
      this.scroller.scrollToIndex(0)
    } else {
      this.isLoadingMore = true
    }

    try {
      const result: ThreadResult = await getThread(appStore.auth.token, this.threadTid, '', '', String(page))
      if (result.ok) {
        if (result.pagination) {
          this.totalPages = result.pagination.totalPages
        }
        this.currentPage = page
        if (result.threadInfo) {
          const info: ThreadInfo = result.threadInfo
          this.threadSubject = info.subject || '帖子'
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
  }

  private async loadPreviousPage(page: number): Promise<void> {
    this.isLoadingPrevious = true
    try {
      const result: ThreadResult = await getThread(appStore.auth.token, this.threadTid, '', '', String(page))
      if (result.ok && result.posts.length > 0) {
        this.loadedPageStart = page
        this.allPosts = [...result.posts, ...this.allPosts]
        this.postsDataSource.prependAll(result.posts)
        // maintainVisibleContentPosition 自动保持可视位置不变
      }
    } catch (e) {
      // 静默失败
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

  private async handleReplySend(text: string): Promise<void> {
    if (!text || !this.threadTid) return
    const isComment: boolean = floatingLayerStore.replyTargetLou > 0
    try {
      const authResult: PostAuthResult = await getPostAuth(appStore.auth.token, this.threadFid, 'reply', Number(this.threadTid), 0, 0)
      if (!authResult.ok) {
        appStore.showToast(authResult.error || '无权回复')
        return
      }

      let result: PostReplyResult
      if (isComment) {
        result = await postComment(appStore.auth.token, Number(this.threadTid), this.replyTargetPid, this.threadFid, text, 0)
      } else {
        result = await postReply(appStore.auth.token, Number(this.threadTid), this.threadFid, text, 0, '', '', 0, 'reply', 0, '')
      }
      if (result.ok) {
        appStore.showToast(isComment ? '评论成功' : '回复成功')
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

  private async handleVote(post: PostInfo, value: number): Promise<void> {
    if (!appStore.auth.isAuthenticated) {
      appStore.showToast('请先登录')
      return
    }
    const pidKey = String(post.pid)
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
      if (msg.length > 0) {
        appStore.showToast(msg)
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
      // 页数选择器遮罩（放在最底层，点击任意位置关闭）
      if (this.showPagePicker) {
        Column().width('100%').height('100%').onClick(() => { this.showPagePicker = false })
      }

      Column() {
        Row() {
        Text('←').fontSize(22).fontColor(AppColors.primary)
          .onClick(() => routerStore.back()).padding({ left: 8, right: 8 })

        Text(this.threadSubject).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('⋯').fontSize(22).fontColor(AppColors.primary)
          .onClick(() => this.handleFavorite()).padding({ left: 4, right: 16 })
      }
      .width('100%').height(44 + this.statusBarHeight)
      .padding({ top: this.statusBarHeight })
      .backgroundColor(AppColors.bgTertiary)
      .border({ width: { bottom: 0.5 }, color: AppColors.separator }).alignItems(VerticalAlign.Center)

      Row() {
        Text('只看楼主').fontSize(13)
          .fontColor(this.authorOnly ? AppColors.primary : AppColors.textTertiary)
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor(this.authorOnly ? AppColors.primaryLight : Color.Transparent)
          .onClick(() => { this.authorOnly = !this.authorOnly })
      }.width('100%').padding({ left: 16, top: 8, bottom: 4 })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(28).height(28).color(AppColors.textTertiary)
          Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 8 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.hasError) {
        Column() {
          Text(this.errorMsg).fontSize(14).fontColor(AppColors.textTertiary).margin({ bottom: 12 })
          Button('重试').fontSize(14).fontColor(AppColors.primary).backgroundColor(AppColors.bgSecondary).borderRadius(10)
            .onClick(() => this.loadPage(1))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List({ scroller: this.scroller }) {
          LazyForEach(this.postsDataSource, (post: PostInfo) => {
            ListItem() {
              PostItem({
                post: post,
                authorOnly: this.authorOnly,
                threadAuthorId: this.threadAuthorId,
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
                  this.replyTargetPid = p.pid
                  floatingLayerStore.replyTargetLou = p.lou
                  floatingLayerStore.replyDialogTitle = `回复 #${p.lou}`
                  floatingLayerStore.replyOnSend = (text: string): Promise<void> => { return this.handleReplySend(text) }
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

            }.width('100%').padding({ top: 12, bottom: 16 })
          }
        }
        .width('100%').layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
        .edgeEffect(EdgeEffect.Spring)
        .maintainVisibleContentPosition(true)
        .onReachEnd(() => {
          if (!this.isLoadingMore && this.currentPage < this.totalPages) {
            this.loadPage(this.currentPage + 1)
          }
        })
        .onReachStart(() => {
          if (!this.isLoadingPrevious && this.loadedPageStart > 1) {
            this.loadPreviousPage(this.loadedPageStart - 1)
          }
        })
      }
    }
    .width('100%').height('100%')

      // 底部工具栏：页数选择器（左）+ 回复按钮（右）
      Row() {
        if (this.totalPages > 1) {
          Row() {
            if (this.totalPages === 2) {
              Stack() {
                Text('1').fontSize(14).fontColor(this.currentPage === 1 ? AppColors.primary : AppColors.textSecondary)
                  .fontWeight(this.currentPage === 1 ? FontWeight.Bold : FontWeight.Regular)
                if (this.currentPage === 1) {
                  Text('•').fontSize(10).fontColor(AppColors.primary)
                    .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
                }
              }.width(24).height(28).onClick(() => this.loadPage(1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text('2').fontSize(14).fontColor(this.currentPage === 2 ? AppColors.primary : AppColors.textSecondary)
                  .fontWeight(this.currentPage === 2 ? FontWeight.Bold : FontWeight.Regular)
                if (this.currentPage === 2) {
                  Text('•').fontSize(10).fontColor(AppColors.primary)
                    .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
                }
              }.width(24).height(28).onClick(() => this.loadPage(2, true))
            } else if (this.currentPage === 1) {
              Stack() {
                Text('1').fontSize(14).fontColor(AppColors.primary).fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPage(1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text('2').fontSize(14).fontColor(AppColors.textSecondary).fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(2, true))
            } else if (this.currentPage === this.totalPages) {
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
                Text(String(this.currentPage - 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(this.currentPage - 1, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.currentPage)).fontSize(14).fontColor(AppColors.primary)
                  .fontWeight(FontWeight.Bold)
                Text('•').fontSize(10).fontColor(AppColors.primary)
                  .position({ x: '50%', y: 22 }).translate({ x: '-50%' })
              }.width(24).height(28).onClick(() => this.loadPage(this.currentPage, true))
              Divider().vertical(true).height(16).color(AppColors.dividerStrong)
              Stack() {
                Text(String(this.currentPage + 1)).fontSize(14).fontColor(AppColors.textSecondary)
                  .fontWeight(FontWeight.Regular)
              }.width(24).height(28).onClick(() => this.loadPage(this.currentPage + 1, true))
            }
            Divider().vertical(true).height(16).color(AppColors.dividerStrong)
            Text('到').fontSize(13).fontColor(AppColors.primary).padding({ left: 4, right: 2 })
              .onClick(() => { this.showPagePicker = !this.showPagePicker })
          }
          .padding({ left: 8, right: 8, top: 0, bottom: 0 })
          .height(40).alignItems(VerticalAlign.Center)
          .backgroundColor(Color.White).borderRadius(20)
          .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
        }

        Blank().layoutWeight(1)

        Stack() {
          Image($r('app.media.icon_reply'))
            .width(20).height(20)
            .fillColor(AppColors.primary)
        }
        .width(40).height(40).borderRadius(20)
        .backgroundColor(Color.White)
        .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
        .onClick(() => {
          this.replyTargetPid = 0
          floatingLayerStore.replyTargetLou = 0
          floatingLayerStore.replyDialogTitle = '写回复'
          floatingLayerStore.replyOnSend = (text: string): Promise<void> => { return this.handleReplySend(text) }
          floatingLayerStore.push(FloatingPage.REPLY_DIALOG)
        })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 + this.navBarHeight }).alignItems(VerticalAlign.Center)

      // 页数选择器弹出面板（定位在页数选择器正上方）
      if (this.totalPages > 1 && this.showPagePicker) {
        Column() {
          Text('选择页面').fontSize(14).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Bold)
            .padding({ top: 12, bottom: 8 }).width('100%').textAlign(TextAlign.Center)
          Divider().color(AppColors.separator)
          Scroll() {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
              ForEach(this.buildPageArray(), (p: number) => {
                Text(String(p)).fontSize(15).fontColor(p === this.currentPage ? AppColors.primary :
                  AppColors.textPrimary).fontWeight(p === this.currentPage ? FontWeight.Bold : FontWeight.Regular)
                  .width(40).height(40).textAlign(TextAlign.Center).borderRadius(8)
                  .backgroundColor(p === this.currentPage ? AppColors.primaryLight : Color.Transparent)
                  .onClick(() => {
                    this.showPagePicker = false
                    if (p !== this.currentPage) {
                      this.loadPage(p, true)
                    }
                  })
              }, (p: number) => String(p))
            }.width('100%')
          }.width('100%').height(120).align(Alignment.TopStart)
        }
        .width(220).height(180).backgroundColor(Color.White).borderRadius(12)
          .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
          .position({ x: 16, y: '100%' }).translate({ y: -256 - this.navBarHeight })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg).alignContent(Alignment.BottomEnd)
    .id('threadPanelRoot')
  }

  private buildPageArray(): number[] {
    const arr: number[] = []
    for (let i: number = 1; i <= this.totalPages; i++) {
      arr.push(i)
    }
    return arr
  }
}
