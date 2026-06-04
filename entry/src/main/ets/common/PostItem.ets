import { AppColors, ImageLoadStrategy } from '../common/Constants'
import { formatTime, escHtml, parseAlterinfoTs, formatTimestampCST } from '../common/Utils'
import { Avatar } from '../common/Avatar'
import { AnonymousName } from '../common/AnonymousName'
import { getCachedBBNodes } from '../service/BBCodeCache'
import { BBCodeContentView } from '../common/BBCodeContentView'
import { PostInfo, PostAttachInfo } from '../service/NgaApi'
import { floatingLayerStore, FloatingPage } from '../store/FloatingLayerStore'
import { appStore } from '../store/AppStore'
import { BBNode, BBNodeType } from '../model/BBCodeNode'
import { AudioPlayer } from '../common/AudioPlayer'
import { ImageSize } from '../common/ImageSizeUtil'
import { fetchVideoSize, getCachedVideoSize } from '../common/VideoSizeUtil'
import { isWifiConnected } from '../common/NetworkUtil'
const VIDEO_EXTS: string[] = ['mp4', 'webm', 'ogg', 'mov', '3gp']
const AUDIO_EXTS: string[] = ['mp3', 'wav', 'flac', 'aac', 'm4a']

@Component
export struct PostItem {
  @Prop post: PostInfo = new PostInfo()
  @Prop isVotedUp: boolean = false
  @Prop isVotedDown: boolean = false
  @Prop holdingHand: number = 0
  @StorageProp('showSignature') showSignature: boolean = true
  @StorageProp('imageLoadStrategy') imageLoadStrategy: string = ImageLoadStrategy.ALWAYS
  @StorageProp('networkChangeVersion') networkChangeVersion: number = 0
  @State private commentsExpanded: boolean = false
  @State private attachsExpanded: boolean = false
  @State private sigExpanded: boolean = false
  @State private videoSizes: Map<string, ImageSize> = new Map()
  @State private menuExpanded: boolean = false
  onImageClick: (urls: string[], index: number) => void = (_urls: string[], _index: number) => {}
  onLinkClick: (href: string) => void = (_href: string) => {}
  onVideoClick: (url: string) => void = (_url: string) => {}
  onProfileClick: (uid: string, screenX: number, screenY: number) => void = (_uid: string, _x: number, _y: number) => {}
  onVote: (post: PostInfo, value: number) => void = (_post: PostInfo, _value: number) => {}
  onReply: (post: PostInfo) => void = (_post: PostInfo) => {}
  onComment: (post: PostInfo) => void = (_post: PostInfo) => {}
  onEdit: (post: PostInfo) => void = (_post: PostInfo) => {}
  onShare: (post: PostInfo) => void = (_post: PostInfo) => {}
  onSummarize: (post: PostInfo) => void = (_post: PostInfo) => {}
  onReadAloud: (post: PostInfo) => void = (_post: PostInfo) => {}
  isTopicAuthor: boolean = false
  isOwnPost: boolean = false

  aboutToReuse(params: Record<string, Object>): void {
    this.commentsExpanded = false
    this.attachsExpanded = false
    this.sigExpanded = false
    this.menuExpanded = false
    this.videoSizes = new Map()
  }

  build() {
    Column() {
        Row() {
          Row() {
            Avatar({ avatar: this.post.avatar, uid: String(this.post.authorid), name: this.post.author, avatarSize: 32 })

            Column() {
              Row() {
                AnonymousName({ author: this.post.author, isAnonymous: this.post.isanonymous, fontSize: 14, normalColor: AppColors.primary })
                if (this.post.userNote && this.post.userNote.length > 0) {
                  Text('(' + this.post.userNote + ')')
                    .fontSize(11).fontColor(AppColors.warning).margin({ left: 4 })
                }
                if (this.isTopicAuthor) {
                  Text('楼主').fontSize(11).fontColor(AppColors.primary).fontWeight(FontWeight.Medium)
                    .margin({ left: 4 })
                }
              }
              Row() {
                if (this.post.memberGroup && this.post.memberGroup.length > 0) {
                  Text(this.post.memberGroup).fontSize(11).fontColor(AppColors.textTertiary)
                }
                Text(formatTime(Number(this.post.postdate))).fontSize(11).fontColor(AppColors.textTertiary).margin({ left: 6 })
              }
            }.alignItems(HorizontalAlign.Start).margin({ left: 8 }).layoutWeight(1)
          }.layoutWeight(1)
          .onClick((event: ClickEvent) => {
            if (this.post.isanonymous) {
              appStore.showToast('该用户已匿名')
              return
            }
            const uid = String(this.post.authorid)
            if (uid) {
              this.onProfileClick(uid, event.windowX, event.windowY)
            }
          })

          Text(this.post.lou === 0 ? '楼主' : this.post.lou === 1 ? '沙发' : `#${this.post.lou}`)
            .fontSize(13).fontColor(AppColors.textTertiary)
        }.width('100%')

        if (this.post.isInBlackList) {
          Text('该用户已被屏蔽').fontSize(14).fontColor(AppColors.textTertiary)
            .margin({ top: 16 }).width('100%').textAlign(TextAlign.Center).padding({ top: 20, bottom: 20 })
        } else {
          Row() {
            Text(this.post.postdate).fontSize(11).fontColor(AppColors.textTertiary)
            if (this.post.alterinfo && this.post.alterinfo.length > 0) {
              Text(this.getEditTimeDisplay()).fontSize(11).fontColor(AppColors.textTertiary)
            }
          }.margin({ top: 12 })

          BBCodeContentView({
            nodes: getCachedBBNodes(this.post.content),
            onImageClick: this.onImageClick,
            onLinkClick: this.onLinkClick,
          }).width('100%').margin({ top: 12 })

          if (this.post.attachs.length > 0) {
            this.AttachmentsSection()
          }

          if (this.showSignature && this.post.signature && this.post.signature.length > 0) {
            Column() {
              Row() {
                Text('签名')
                  .fontSize(10).fontColor(AppColors.textTertiary)
                Image($r('app.media.icon_chevron_down'))
                  .width(12).height(12).fillColor(AppColors.textTertiary)
                  .rotate({ angle: this.sigExpanded ? 180 : 0 })
                  .margin({ left: 2 })
              }
              .margin({ bottom: 4 })
              .onClick(() => { this.sigExpanded = !this.sigExpanded })

              Column() {
                BBCodeContentView({
                  nodes: getCachedBBNodes(this.post.signature),
                  onImageClick: this.onImageClick,
                  onLinkClick: this.onLinkClick,
                  hideFailedImages: true,
                })
              }
              .constraintSize({ maxHeight: this.sigExpanded ? 10000 : 150 })
              .clip(true)
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 12 })
            .padding({ left: 10, top: 4, bottom: 4 })
            .border({ width: { left: 2 }, color: AppColors.separator })
          }

          if (this.post.comments.length > 0) {
            this.CommentsSection()
          }

          this.VoteBar()
        }
      }
      .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  AttachmentsSection() {
    Row() {
      Row() {
        if (!this.attachsExpanded) {
          Image($r('app.media.icon_attachment')).width(13).height(13).fillColor(AppColors.textTertiary).margin({ right: 4 })
        }
        Text(this.attachsExpanded ? '收起附件' : `附件 (${this.post.attachs.length})`).fontSize(13).fontColor(AppColors.textTertiary)
      }
        .onClick(() => {
          this.attachsExpanded = !this.attachsExpanded
          if (this.attachsExpanded) {
            this.fetchAttachVideoSizes()
          }
        })
      }.margin({ top: 12 })
      if (this.attachsExpanded) {
      Column() {
        ForEach(this.post.attachs, (att: PostAttachInfo) => {
          this.renderVideoAttach(att)
        })
        ForEach(this.post.attachs, (att: PostAttachInfo) => {
          this.renderAudioAttach(att)
        })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.post.attachs, (att: PostAttachInfo) => {
            this.renderImageAttach(att)
          })
        }
      }.margin({ top: 4 })
    }
  }

  @Builder
  renderVideoAttach(att: PostAttachInfo) {
    if (VIDEO_EXTS.indexOf(att.ext.toLowerCase()) >= 0) {
      Video({ src: att.attachurl })
        .width('100%').aspectRatio(this.getAttachVideoAspectRatio(att.attachurl)).objectFit(ImageFit.Contain)
        .controls(true)
        .borderRadius(8).backgroundColor(AppColors.bgSecondary)
        .autoPlay(false).margin({ bottom: 6 })
    }
  }

  @Builder
  renderAudioAttach(att: PostAttachInfo) {
    if (AUDIO_EXTS.indexOf(att.ext.toLowerCase()) >= 0) {
      AudioPlayer({ src: att.attachurl })
        .margin({ bottom: 6 })
    }
  }

  @Builder
  renderImageAttach(att: PostAttachInfo) {
    if (VIDEO_EXTS.indexOf(att.ext.toLowerCase()) < 0 && AUDIO_EXTS.indexOf(att.ext.toLowerCase()) < 0) {
      if (this.shouldUsePassive()) {
        Stack() {
          Image($r('app.media.icon_image'))
            .width(20).height(20)
            .fillColor(AppColors.textTertiary)
            .opacity(0.45)
        }
        .width(100).height(100).borderRadius(8)
        .backgroundColor(AppColors.bgSecondary)
        .margin({ right: 6, top: 6 })
        .onClick(() => { this.dispatchAttachClick(att.attachurl) })
      } else {
        Image(att.attachurl).width(100).height(100).borderRadius(8)
          .objectFit(ImageFit.Cover).backgroundColor(AppColors.bgSecondary)
          .margin({ right: 6, top: 6 }).onError(() => {})
          .onClick(() => { this.dispatchAttachClick(att.attachurl) })
      }
    }
  }

   @Builder
  VoteBar() {
    Row() {
       if (this.holdingHand === 1) {
         Row() {
           Row() {
             Row() {
               Image($r('app.media.icon_more'))
                 .width(16).height(16)
                 .fillColor(this.menuExpanded ? AppColors.primary : AppColors.textTertiary)
                 .rotate({ angle: this.menuExpanded ? -90 : 0 })
             }
             .padding({ left: 6, right: 6, top: 4, bottom: 4 })
             .borderRadius(6)
             .alignItems(VerticalAlign.Center)
             .onClick(() => { this.getUIContext()?.animateTo({ duration: 150, curve: Curve.EaseInOut }, () => { this.menuExpanded = !this.menuExpanded }) })

              if (this.menuExpanded) {
                Row() {
                  Image($r('app.media.icon_ai'))
                    .width(16).height(16)
                    .fillColor(AppColors.textTertiary)
                }
                .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                .borderRadius(6)
                .margin({ left: 6 })
                .alignItems(VerticalAlign.Center)
                .transition(TransitionEffect.OPACITY)
                .onClick(() => this.onSummarize(this.post))

                Row() {
                  Image($r('app.media.icon_volume_up'))
                    .width(16).height(16)
                    .fillColor(AppColors.textTertiary)
                }
                .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                .borderRadius(6)
                .margin({ left: 6 })
                .alignItems(VerticalAlign.Center)
                .transition(TransitionEffect.OPACITY)
                .onClick(() => this.onReadAloud(this.post))

                Row() {
                  Image($r('app.media.icon_share'))
                    .width(16).height(16)
                    .fillColor(AppColors.textTertiary)
                }
                .padding({ left: 6, right: 6, top: 4, bottom: 4 })
                .borderRadius(6)
                .margin({ left: 6 })
                .alignItems(VerticalAlign.Center)
                .transition(TransitionEffect.OPACITY)
                .onClick(() => this.onShare(this.post))
              }

              if (this.isOwnPost) {
               Row() {
                 Image($r('app.media.icon_compose'))
                   .width(16).height(16)
                   .fillColor(AppColors.textTertiary)
               }
               .padding({ left: 6, right: 6, top: 4, bottom: 4 })
               .borderRadius(6)
               .margin({ left: 6 })
               .alignItems(VerticalAlign.Center)
               .onClick(() => this.onEdit(this.post))
             }

             Row() {
               Image($r('app.media.icon_reply'))
                 .width(16).height(16)
                 .fillColor(AppColors.textTertiary)
             }
             .padding({ left: 6, right: 6, top: 4, bottom: 4 })
             .borderRadius(6)
             .margin({ left: 6 })
             .alignItems(VerticalAlign.Center)
             .onClick(() => this.onReply(this.post))

             Row() {
               Image($r('app.media.icon_thumb_down'))
                 .width(16).height(16)
                 .fillColor(this.isVotedDown ? AppColors.destructive : AppColors.textTertiary)
               if (this.post.score_2 > 0 || this.isVotedDown) {
                 Text(String(this.post.score_2))
                   .fontSize(13)
                   .fontColor(this.isVotedDown ? AppColors.destructive : AppColors.textSecondary)
                   .margin({ left: 3 })
               }
             }
             .padding({ left: 6, right: 6, top: 4, bottom: 4 })
             .borderRadius(6)
             .margin({ left: 6 })
             .alignItems(VerticalAlign.Center)
             .onClick(() => this.onVote(this.post, -1))

             Row() {
               Image($r('app.media.icon_thumb_up'))
                 .width(16).height(16)
                 .fillColor(this.isVotedUp ? AppColors.primary : AppColors.textTertiary)
               if (this.post.score > 0 || this.isVotedUp) {
                 Text(String(this.post.score))
                   .fontSize(13)
                   .fontColor(this.isVotedUp ? AppColors.primary : AppColors.textSecondary)
                   .margin({ left: 3 })
               }
             }
             .padding({ left: 6, right: 6, top: 4, bottom: 4 })
             .borderRadius(6)
             .margin({ left: 6 })
             .alignItems(VerticalAlign.Center)
             .onClick(() => this.onVote(this.post, 1))
           }
           .alignItems(VerticalAlign.Center)
           .transition(TransitionEffect.OPACITY)

            Row().layoutWeight(1)
          }
       } else {
         Row().layoutWeight(1)
        Row() {
          Row() {
            Image($r('app.media.icon_thumb_up'))
              .width(16).height(16)
              .fillColor(this.isVotedUp ? AppColors.primary : AppColors.textTertiary)
            if (this.post.score > 0 || this.isVotedUp) {
              Text(String(this.post.score))
                .fontSize(13)
                .fontColor(this.isVotedUp ? AppColors.primary : AppColors.textSecondary)
                .margin({ left: 3 })
            }
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(6)
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.onVote(this.post, 1))

          Row() {
            Image($r('app.media.icon_thumb_down'))
              .width(16).height(16)
              .fillColor(this.isVotedDown ? AppColors.destructive : AppColors.textTertiary)
            if (this.post.score_2 > 0 || this.isVotedDown) {
              Text(String(this.post.score_2))
                .fontSize(13)
                .fontColor(this.isVotedDown ? AppColors.destructive : AppColors.textSecondary)
                .margin({ left: 3 })
            }
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(6)
          .margin({ left: 6 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.onVote(this.post, -1))

          Row() {
            Image($r('app.media.icon_reply'))
              .width(16).height(16)
              .fillColor(AppColors.textTertiary)
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(6)
          .margin({ left: 6 })
          .alignItems(VerticalAlign.Center)
           .onClick(() => this.onReply(this.post))

          if (this.isOwnPost) {
            Row() {
              Image($r('app.media.icon_compose'))
                .width(16).height(16)
                .fillColor(AppColors.textTertiary)
            }
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .borderRadius(6)
            .margin({ left: 6 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => this.onEdit(this.post))
          }

          if (this.menuExpanded) {
            Row() {
              Image($r('app.media.icon_share'))
                .width(16).height(16)
                .fillColor(AppColors.textTertiary)
            }
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .borderRadius(6)
            .margin({ left: 6 })
            .alignItems(VerticalAlign.Center)
            .transition(TransitionEffect.OPACITY)
            .onClick(() => this.onShare(this.post))

            Row() {
              Image($r('app.media.icon_ai'))
                .width(16).height(16)
                .fillColor(AppColors.textTertiary)
            }
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .borderRadius(6)
            .margin({ left: 6 })
            .alignItems(VerticalAlign.Center)
            .transition(TransitionEffect.OPACITY)
            .onClick(() => this.onSummarize(this.post))

            Row() {
              Image($r('app.media.icon_volume_up'))
                .width(16).height(16)
                .fillColor(AppColors.textTertiary)
            }
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .borderRadius(6)
            .margin({ left: 6 })
            .alignItems(VerticalAlign.Center)
            .transition(TransitionEffect.OPACITY)
            .onClick(() => this.onReadAloud(this.post))
          }

          Row() {
            Image($r('app.media.icon_more'))
              .width(16).height(16)
              .fillColor(this.menuExpanded ? AppColors.primary : AppColors.textTertiary)
              .rotate({ angle: this.menuExpanded ? 90 : 0 })
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(6)
          .margin({ left: 6 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.getUIContext()?.animateTo({ duration: 150, curve: Curve.EaseInOut }, () => { this.menuExpanded = !this.menuExpanded }) })
        }
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY)
      }
    }.width('100%').margin({ top: 12 }).alignItems(VerticalAlign.Center)
  }

  @Builder
  CommentsSection() {
    Column() {
      ForEach(this.commentsExpanded ? this.post.comments : this.post.comments.slice(0, 2), (c: PostInfo) => {
        Row() {
          Avatar({ avatar: c.avatar, uid: String(c.authorid), name: c.author, avatarSize: 24 })
            .onClick((event: ClickEvent) => {
              if (c.isanonymous) {
                appStore.showToast('该用户已匿名')
                return
              }
              const uid = String(c.authorid)
              if (uid) {
                this.onProfileClick(uid, event.windowX, event.windowY)
              }
            })

          Column() {
            Row() {
              AnonymousName({ author: c.author, isAnonymous: c.isanonymous, fontSize: 12, normalColor: AppColors.primary })
              if (appStore.getNote(String(c.authorid)).length > 0) {
                Text('(' + appStore.getNote(String(c.authorid)) + ')')
                  .fontSize(10).fontColor(AppColors.warning).margin({ left: 3 })
              }
            }

            BBCodeContentView({
              nodes: filterBBTags(getCachedBBNodes(c.content), [BBNodeType.QUOTE, BBNodeType.POST_BY]),
              onImageClick: this.onImageClick,
              onLinkClick: this.onLinkClick,
            }).width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 8 })
        }
        .width('100%').alignItems(VerticalAlign.Top).padding({ top: 6, bottom: 6 })
      }, (c: PostInfo) => String(c.pid))
      if (this.post.comments.length > 2) {
        Text(this.commentsExpanded ? '收起' : `查看全部 ${this.post.comments.length} 条评论`)
          .fontSize(12).fontColor(AppColors.primary).margin({ top: 4 })
          .onClick(() => { this.commentsExpanded = !this.commentsExpanded })
      }
    }
    .width('80%').alignSelf(ItemAlign.End).padding(12).backgroundColor(AppColors.bgSecondary).borderRadius(8).margin({ top: 12 })
  }

  private getAttachVideoAspectRatio(url: string): number {
    const size: ImageSize | undefined = this.videoSizes.get(url)
    if (size && size.width > 0 && size.height > 0) {
      return size.width / size.height
    }
    return 16 / 9
  }

  private setAttachVideoSize(url: string, size: ImageSize): void {
    const m: Map<string, ImageSize> = new Map()
    this.videoSizes.forEach((v: ImageSize, k: string) => { m.set(k, v) })
    m.set(url, size)
    this.videoSizes = m
  }

  private getEditTimeDisplay(): string {
    if (!this.post.alterinfo || this.post.alterinfo.length === 0) return ''
    const et: number | null = parseAlterinfoTs(this.post.alterinfo)
    if (et === null) return ''
    return ' [在' + formatTimestampCST(et) + '修改]'
  }

  private dispatchAttachClick(targetUrl: string): void {
    const urls: string[] = []
    for (let i = 0; i < this.post.attachs.length; i++) {
      const url = this.post.attachs[i].attachurl
      if (url && url.length > 0) {
        urls.push(url)
      }
    }
    if (urls.length > 0) {
      let idx = 0
      for (let i = 0; i < urls.length; i++) {
        if (urls[i] === targetUrl) {
          idx = i
          break
        }
      }
      this.onImageClick(urls, idx)
    }
  }

  private shouldUsePassive(): boolean {
    let strategy: string = this.imageLoadStrategy
    if (strategy === ImageLoadStrategy.ALWAYS) {
      return false
    }
    if (strategy === ImageLoadStrategy.MANUAL) {
      return true
    }
    return !isWifiConnected()
  }

  private fetchAttachVideoSizes(): void {
    for (let i = 0; i < this.post.attachs.length; i++) {
      const att: PostAttachInfo = this.post.attachs[i]
      if (VIDEO_EXTS.indexOf(att.ext.toLowerCase()) >= 0 && att.attachurl.length > 0) {
        const cached: ImageSize | null = getCachedVideoSize(att.attachurl)
        if (cached) {
          this.setAttachVideoSize(att.attachurl, cached)
        } else if (!this.videoSizes.has(att.attachurl)) {
          fetchVideoSize(att.attachurl).then((size: ImageSize | null) => {
            if (size) {
              this.setAttachVideoSize(att.attachurl, size)
            }
          })
        }
      }
    }
  }
}


function filterBBTags(nodes: BBNode[], skipTypes: BBNodeType[]): BBNode[] {
  const result: BBNode[] = []
  for (const node of nodes) {
    if (skipTypes.indexOf(node.type) >= 0) continue
    if (node.children.length > 0) {
      const n = new BBNode()
      n.type = node.type
      n.text = node.text
      n.id = node.id
      n.href = node.href
      n.color = node.color
      n.size = node.size
      n.src = node.src
      n.title = node.title
      n.emotionCat = node.emotionCat
      n.emotionCode = node.emotionCode
      n.fontFamily = node.fontFamily
      n.align = node.align
      n.colSpan = node.colSpan
      n.rowSpan = node.rowSpan
      n.colWidth = node.colWidth
      n.children = filterBBTags(node.children, skipTypes)
      result.push(n)
    } else {
      result.push(node)
    }
  }
  return result
}
