/**
 * 嵌入式帖子详情面板 - 用于 md/lg 布局的右侧列
 * 复刻 React ThreadPage 的嵌入模式
 * 返回操作通过 routerStore.back() 实现
 */

import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { getThread, getPostAuth, postReply, addFavorite, ThreadResult, PostInfo, PostAttachInfo, PostAuthResult, PostReplyResult } from '../service/NgaApi'
import { AppColors } from '../common/Constants'
import { formatTime, escHtml } from '../common/Utils'
import router from '@ohos.router'
import { componentUtils } from '@kit.ArkUI'
import { Avatar } from '../common/Avatar'
import { parseBBCode } from '../service/BBCodeParser'
import { ProfileCardPopup } from '../common/ProfileCardPopup'
import { BBCodeContentView } from '../common/BBCodeContentView'

@CustomDialog
struct ThreadReplyDialog {
  controller: CustomDialogController
  @State replyText: string = ''
  @State sending: boolean = false
  dialogTitle: string = '回复'
  onSend?: (text: string) => void
  onClose?: () => void

  build() {
    Column() {
      Divider().width(36).height(4).borderRadius(2).color('#D1D1D6').margin({ top: 8, bottom: 12 })
      Row() {
        Text(this.dialogTitle).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('取消').fontSize(15).fontColor(AppColors.textTertiary).backgroundColor(Color.Transparent)
          .onClick(() => { if (this.onClose) { this.onClose() } else { this.controller.close() } })
      }.width('100%').padding({ left: 16, right: 16 })

      TextArea({ text: this.replyText, placeholder: '写回复...' })
        .width('92%').height(120).margin({ top: 12 }).padding(12).fontSize(15)
        .borderRadius(12).backgroundColor(AppColors.bgSecondary)
        .onChange((value: string) => { this.replyText = value })

      Button(this.sending ? '发送中...' : '发送')
        .width('92%').height(44).margin({ top: 12, bottom: 20 }).fontSize(16)
        .fontColor(Color.White).backgroundColor(AppColors.primary).borderRadius(12)
        .enabled(!this.sending && this.replyText.trim().length > 0)
        .onClick(() => {
          if (this.onSend && this.replyText.trim()) {
            this.sending = true
            this.onSend(this.replyText.trim())
            this.sending = false
          }
        })
    }
    .backgroundColor(AppColors.bg).borderRadius({ topLeft: 14, topRight: 14 }).alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct ThreadPanel {
  @Prop @Watch('onThreadChanged') threadTid: string = ''
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State errorMsg: string = ''
  @State allPosts: PostInfo[] = []
  @State currentPage: number = 1
  @State totalPages: number = 0
  @State isLoadingMore: boolean = false
  @State authorOnly: boolean = false
  @State favDone: boolean = false
  @State threadSubject: string = '帖子'
  @State threadFid: number = 0
  @State threadAuthorId: string = ''
  @State expandedSigs: Set<string> = new Set()
  @State expandedComments: Set<string> = new Set()
  @State expandedAttachs: Set<string> = new Set()
  @State @Watch('onImageViewerChanged') imageViewerVisible: boolean = false
  @State imageViewerUrls: string[] = []
  @State imageViewerInitialIndex: number = 0
  @State imageViewerCurrentIndex: number = 0
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('profileCardVisible') @Watch('onExternalProfileCardClose') storageProfileCardVis: boolean = false

  @State showReplyDialog: boolean = false
  @State profileCardUid: string = ''
  @State @Watch('onProfileCardVisChanged') profileCardVisible: boolean = false
  @State profileCardScreenX: number = 0
  @State profileCardScreenY: number = 0
  private scroller: Scroller = new Scroller()
  private replyTargetPid: number = 0

  private showProfileCard(uid: string, screenX: number, screenY: number): void {
    this.profileCardUid = uid
    const cardW: number = 280
    const cardH: number = 400
    const pad: number = 8
    try {
      const info = componentUtils.getRectangleById('threadPanelRoot')
      const context = this.getUIContext()
      const rootX = context.px2vp(Number(info.windowOffset.x))
      const rootY = context.px2vp(Number(info.windowOffset.y))
      const rootW = context.px2vp(Number(info.size.width))
      const rootH = context.px2vp(Number(info.size.height))
      const localX = screenX - rootX
      const localY = screenY - rootY
      this.profileCardScreenX = Math.max(pad, Math.min(localX - cardW / 2, rootW - cardW - pad))
      this.profileCardScreenY = Math.max(pad, Math.min(localY + pad, rootH - cardH - pad))
    } catch (e) {
      this.profileCardScreenX = screenX - cardW / 2
      this.profileCardScreenY = screenY + pad
    }
    this.profileCardVisible = true
  }

  private onProfileCardVisChanged(): void {
    AppStorage.setOrCreate('profileCardVisible', this.profileCardVisible)
  }

  private onExternalProfileCardClose(): void {
    if (!this.storageProfileCardVis && this.profileCardVisible) {
      this.profileCardVisible = false
    }
  }

  private onImageViewerChanged(): void {
    AppStorage.setOrCreate('imageViewerVisible', this.imageViewerVisible)
  }

  aboutToAppear(): void {
    this.loadPage(1)
  }

  private onThreadChanged(): void {
    this.allPosts = []
    this.currentPage = 1
    this.totalPages = 0
    this.hasError = false
    this.authorOnly = false
    this.favDone = false
    this.expandedSigs = new Set()
    this.expandedComments = new Set()
    this.expandedAttachs = new Set()
    this.loadPage(1)
  }

  private async loadPage(page: number): Promise<void> {
    if (page === 1) {
      this.isLoading = true
      this.hasError = false
      this.scroller.scrollToIndex(0)
    } else {
      this.isLoadingMore = true
    }

    try {
      const result: ThreadResult = await getThread(appStore.auth.token, this.threadTid, '', '', String(page))
      if (result.ok) {
        if (result.threadInfo) {
          const info = result.threadInfo as Record<string, Object>
          this.threadSubject = String(info['subject'] ?? '帖子')
          this.threadFid = Number(info['fid'] ?? 0)
          this.threadAuthorId = String(info['authorid'] ?? '')
        }
        if (result.pagination) {
          this.totalPages = result.pagination.totalPages
        }
        if (page === 1) {
          this.allPosts = result.posts
        } else {
          const arr: PostInfo[] = []
          for (let i = 0; i < this.allPosts.length; i++) arr.push(this.allPosts[i])
          for (let i = 0; i < result.posts.length; i++) arr.push(result.posts[i])
          this.allPosts = arr
        }
        this.currentPage = page
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

  private async handleReplySend(text: string): Promise<void> {
    if (!text || !this.threadTid) return
    try {
      const authResult: PostAuthResult = await getPostAuth(appStore.auth.token, this.threadFid, 'reply', Number(this.threadTid), 0, 0)
      if (!authResult.ok) {
        appStore.showToast('无权回复')
        return
      }

      let result: PostReplyResult
      if (this.replyTargetPid > 0) {
        result = await postReply(appStore.auth.token, Number(this.threadTid), this.threadFid, text, 0, '', '', 0, 'comment', this.replyTargetPid, '')
      } else {
        result = await postReply(appStore.auth.token, Number(this.threadTid), this.threadFid, text, 0, '', '', 0, 'reply', 0, '')
      }
      if (result.ok) {
        appStore.showToast(this.replyTargetPid > 0 ? '评论成功' : '回复成功')
        this.allPosts = []
        this.loadPage(1)
      } else {
        appStore.showToast(result.error || '操作失败')
      }
    } catch (e) {
      appStore.showToast((e as Error).message || '操作失败')
    }
    this.showReplyDialog = false
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

  build() {
    Stack() {
      Column() {
        // 嵌入式导航栏 - 返回使用 routerStore.back()
        Row() {
        Text('←').fontSize(22).fontColor(AppColors.primary)
          .onClick(() => routerStore.back()).padding({ left: 8, right: 8 })
        Text(this.threadSubject).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('⋯').fontSize(22).fontColor(AppColors.primary)
          .onClick(() => this.handleFavorite()).padding({ left: 8, right: 16 })
      }
      .width('100%').height(44).backgroundColor(AppColors.bgTertiary)
      .border({ width: { bottom: 0.5 }, color: AppColors.separator }).alignItems(VerticalAlign.Center)

      // 只看楼主
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
          ForEach(this.allPosts, (post: PostInfo) => {
            ListItem() {
              this.PostItem(post)
            }
          })
          ListItem() {
            Row() {
              if (this.isLoadingMore) {
                LoadingProgress().width(16).height(16).color(AppColors.textTertiary)
                Text('加载更多...').fontSize(13).fontColor(AppColors.textTertiary).margin({ left: 8 })
              } else if (this.currentPage >= this.totalPages && this.allPosts.length > 0) {
                Text('已加载全部回复').fontSize(13).fontColor(AppColors.textTertiary)
              }
            }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 16, bottom: 16 })
          }
        }
        .width('100%').layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          if (!this.isLoadingMore && this.currentPage < this.totalPages) {
            this.loadPage(this.currentPage + 1)
          }
        })
      }
    }
    .width('100%').height('100%')

      // 浮动回复按钮
      Row() {
        Stack() {
          Image($r('app.media.icon_reply'))
            .width(20).height(20)
            .fillColor(AppColors.primary)
        }
        .width(40).height(40).borderRadius(20)
        .backgroundColor(Color.White)
        .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
        .onClick(() => { this.replyTargetPid = 0; this.showReplyDialog = true })
      }.width('100%').justifyContent(FlexAlign.End).padding({ right: 16, bottom: 16 })

      if (this.imageViewerVisible) {
        this.ImageViewerBuilder()
      }

      if (this.profileCardVisible) {
        this.ProfileCardOverlay()
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg).alignContent(Alignment.BottomEnd)
    .id('threadPanelRoot')
    .bindContentCover(this.showReplyDialog, this.ReplyDialogBuilder())
  }

  @Builder
  ReplyDialogBuilder() {
    ThreadReplyDialog({
      dialogTitle: this.replyTargetPid > 0 ? '评论' : '回复',
      onSend: (text: string) => this.handleReplySend(text),
      onClose: () => { this.showReplyDialog = false }
    })
  }

  @Builder
  ProfileCardOverlay() {
    Stack() {
      ProfileCardPopup({
        targetUid: this.profileCardUid,
        currentBreakpoint: this.currentBreakpoint,
        onClose: () => { this.profileCardVisible = false }
      })
        .position({
          x: this.profileCardScreenX,
          y: this.profileCardScreenY
        })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => { this.profileCardVisible = false })
  }

  @Builder
  PostItem(post: PostInfo) {
    if (this.authorOnly && this.threadAuthorId.length > 0 && String(post.authorid) !== this.threadAuthorId) {
      // 不渲染
    } else {
      Column() {
        Row() {
          Row() {
            Avatar({ avatar: post.avatar, uid: String(post.authorid), name: post.author, avatarSize: 32 })

            Column() {
              Text(escHtml(post.author)).fontSize(14).fontColor(AppColors.primary).fontWeight(FontWeight.Medium)
              Row() {
                if (post.memberGroup && post.memberGroup.length > 0) {
                  Text(post.memberGroup).fontSize(11).fontColor(AppColors.textTertiary)
                }
                Text(formatTime(Number(post.postdate))).fontSize(11).fontColor(AppColors.textTertiary).margin({ left: 6 })
              }
            }.alignItems(HorizontalAlign.Start).margin({ left: 8 }).layoutWeight(1)
          }.layoutWeight(1)
          .onClick((event: ClickEvent) => {
            const uid = String(post.authorid)
            if (uid) {
              this.showProfileCard(uid, event.screenX, event.screenY)
            }
          })

          Text(`#${post.lou}`).fontSize(13).fontColor(AppColors.textTertiary)
        }.width('100%')

        if (post.isInBlackList) {
          Text('该用户已被屏蔽').fontSize(14).fontColor(AppColors.textTertiary)
            .margin({ top: 12 }).width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
        } else {
          BBCodeContentView({
            nodes: parseBBCode(post.content),
            onImageClick: (urls: string[], index: number): void => {
              this.imageViewerUrls = urls
              this.imageViewerInitialIndex = index
              this.imageViewerCurrentIndex = index
              this.imageViewerVisible = true
            },
            onLinkClick: (href: string) => {
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
                const page = parseInt(pageStr, 10) || 1
                if (tid.length > 0) {
                  routerStore.navigateActivity(Screen.thread(tid, page))
                }
              } else if (href.startsWith('#/profile?')) {
                const uidStr = href.split('uid=')[1]
                if (uidStr) {
                  this.showProfileCard(uidStr.split('&')[0], 200, 200)
                }
              }
            }
          }).width('100%').margin({ top: 8 })

          if (post.attachs.length > 0) {
            Row() {
              Text(this.expandedAttachs.has(String(post.pid)) ? '收起附件' : `📎 附件 (${post.attachs.length})`)
                .fontSize(13).fontColor(AppColors.textTertiary)
                .onClick(() => {
                  const s = new Set(this.expandedAttachs)
                  if (s.has(String(post.pid))) { s.delete(String(post.pid)) } else { s.add(String(post.pid)) }
                  this.expandedAttachs = s
                })
            }.margin({ top: 8 })
            if (this.expandedAttachs.has(String(post.pid))) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(post.attachs, (att: PostAttachInfo, index: number) => {
                  Image(att.thumb || att.attachurl).width(100).height(100).borderRadius(8)
                    .objectFit(ImageFit.Cover).backgroundColor(AppColors.bgSecondary)
                    .margin({ right: 6, top: 6 }).onError(() => {})
                    .onClick(() => {
                      const urls: string[] = []
                      for (let i = 0; i < post.attachs.length; i++) {
                        const url = post.attachs[i].attachurl
                        if (url && url.length > 0) {
                          urls.push(url)
                        }
                      }
                      if (urls.length > 0) {
                        let idx = 0
                        const clickedUrl = att.attachurl
                        for (let i = 0; i < urls.length; i++) {
                          if (urls[i] === clickedUrl) {
                            idx = i
                            break
                          }
                        }
                        this.imageViewerUrls = urls
                        this.imageViewerInitialIndex = idx
                        this.imageViewerCurrentIndex = idx
                        this.imageViewerVisible = true
                      }
                    })
                })
              }.margin({ top: 4 })
            }
          }

          if (post.signature && post.signature.length > 0) {
            Row() {
              Text(this.expandedSigs.has(String(post.pid)) ? '收起签名' : '查看签名')
                .fontSize(12).fontColor(AppColors.textTertiary)
                .onClick(() => {
                  const s = new Set(this.expandedSigs)
                  if (s.has(String(post.pid))) { s.delete(String(post.pid)) } else { s.add(String(post.pid)) }
                  this.expandedSigs = s
                })
            }.margin({ top: 8 })
            if (this.expandedSigs.has(String(post.pid))) {
              Column() {
                BBCodeContentView({
                  nodes: parseBBCode(post.signature),
                  onImageClick: (urls: string[], index: number): void => {
                    this.imageViewerUrls = urls
                    this.imageViewerInitialIndex = index
                    this.imageViewerCurrentIndex = index
                    this.imageViewerVisible = true
                  },
                  onLinkClick: (href: string) => {
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
                      const page = parseInt(pageStr, 10) || 1
                      if (tid.length > 0) {
                        routerStore.navigateActivity(Screen.thread(tid, page))
                      }
                    } else if (href.startsWith('#/profile?')) {
                      const uidStr = href.split('uid=')[1]
                      if (uidStr) {
                        this.showProfileCard(uidStr.split('&')[0], 200, 200)
                      }
                    }
                  }
                })
              }
              .margin({ top: 4 }).padding({ top: 4 }).border({ width: { top: 0.5 }, color: AppColors.separator })
            }
          }

          Row() {
            if (post.score > 0) {
              Text(`👍 ${post.score}`).fontSize(13).fontColor(AppColors.primary)
            }
            Text('回复').fontSize(13).fontColor(AppColors.textTertiary)
              .onClick(() => {
                this.replyTargetPid = post.pid
                this.showReplyDialog = true
              })
          }.width('100%').justifyContent(FlexAlign.End).margin({ top: 8 })

          if (post.comments.length > 0) {
            Column() {
              ForEach(this.expandedComments.has(String(post.pid)) ? post.comments : post.comments.slice(0, 2), (c: PostInfo) => {
                Row() {
                  Text(escHtml(c.author)).fontSize(13).fontColor(AppColors.primary).fontWeight(FontWeight.Medium)
                    .onClick((event: ClickEvent) => {
                      const uid = String(c.authorid)
                      if (uid) {
                        this.showProfileCard(uid, event.screenX, event.screenY)
                      }
                    })
                  Text(': ').fontSize(13).fontColor(AppColors.textTertiary)
                  Text(escHtml(c.content)).fontSize(13).fontColor(AppColors.textSecondary).layoutWeight(1)
                }.width('100%').padding({ top: 2, bottom: 2 })
              })
              if (post.comments.length > 2) {
                Text(this.expandedComments.has(String(post.pid)) ? '收起' : `查看全部 ${post.comments.length} 条评论`)
                  .fontSize(12).fontColor(AppColors.primary).margin({ top: 4 })
                  .onClick(() => {
                    const s = new Set(this.expandedComments)
                    if (s.has(String(post.pid))) { s.delete(String(post.pid)) } else { s.add(String(post.pid)) }
                    this.expandedComments = s
                  })
              }
            }
            .width('100%').padding(10).backgroundColor(AppColors.bgSecondary).borderRadius(8).margin({ top: 8 })
          }
        }
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 }).alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ImageViewerBuilder() {
    Column() {
      Row() {
        Blank().layoutWeight(1)
        Text('✕').fontSize(24).fontColor(Color.White).padding({ right: 16, top: 16 })
          .onClick(() => { this.imageViewerVisible = false })
      }.width('100%')

      Swiper() {
        ForEach(this.imageViewerUrls, (url: string) => {
          Image(url).objectFit(ImageFit.Contain).width('100%').onError(() => {})
        })
      }
      .index(this.imageViewerInitialIndex)
      .indicator(this.imageViewerUrls.length > 1)
      .loop(false)
      .onChange((index: number) => { this.imageViewerCurrentIndex = index })
      .layoutWeight(1)
      .width('100%')

      if (this.imageViewerUrls.length > 1) {
        Text(`${this.imageViewerCurrentIndex + 1} / ${this.imageViewerUrls.length}`)
          .fontSize(16).fontColor(Color.White).margin({ top: 12, bottom: 32 })
      } else {
        Blank().height(32)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Color.Black)
  }
}
