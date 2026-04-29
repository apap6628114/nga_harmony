import { AppColors } from '../common/Constants'
import { formatTime, escHtml } from '../common/Utils'
import { Avatar } from '../common/Avatar'
import { AnonymousName } from '../common/AnonymousName'
import { getCachedBBNodes } from '../service/BBCodeCache'
import { BBCodeContentView } from '../common/BBCodeContentView'
import { PostInfo, PostAttachInfo } from '../service/NgaApi'
import { floatingLayerStore, FloatingPage } from '../store/FloatingLayerStore'
import { appStore } from '../store/AppStore'

@Component
export struct PostItem {
  @Prop post: PostInfo = new PostInfo()
  @Prop votedUpPids: Set<string> = new Set()
  @Prop votedDownPids: Set<string> = new Set()
  @State private sigExpanded: boolean = false
  @State private commentsExpanded: boolean = false
  @State private attachsExpanded: boolean = false
  onImageClick: (urls: string[], index: number) => void = (_urls: string[], _index: number) => {}
  onLinkClick: (href: string) => void = (_href: string) => {}
  onProfileClick: (uid: string, screenX: number, screenY: number) => void = (_uid: string, _x: number, _y: number) => {}
  onVote: (post: PostInfo, value: number) => void = (_post: PostInfo, _value: number) => {}
  onReply: (post: PostInfo) => void = (_post: PostInfo) => {}
  onComment: (post: PostInfo) => void = (_post: PostInfo) => {}

  build() {
    Column() {
        Row() {
          Row() {
            Avatar({ avatar: this.post.avatar, uid: String(this.post.authorid), name: this.post.author, avatarSize: 32 })

            Column() {
              AnonymousName({ author: this.post.author, isAnonymous: this.post.isanonymous, fontSize: 14, normalColor: AppColors.primary })
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
              appStore.showToast('这白痴匿名了,神马都看不到')
              return
            }
            const uid = String(this.post.authorid)
            if (uid) {
              this.onProfileClick(uid, event.screenX, event.screenY)
            }
          })

          Text(this.post.lou === 0 ? '楼主' : this.post.lou === 1 ? '沙发' : `#${this.post.lou}`)
            .fontSize(13).fontColor(AppColors.textTertiary)
        }.width('100%')

        if (this.post.isInBlackList) {
          Text('该用户已被屏蔽').fontSize(14).fontColor(AppColors.textTertiary)
            .margin({ top: 12 }).width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
        } else {
          BBCodeContentView({
            nodes: getCachedBBNodes(this.post.content),
            onImageClick: this.onImageClick,
            onLinkClick: this.onLinkClick,
          }).width('100%').margin({ top: 8 })

          if (this.post.attachs.length > 0) {
            this.AttachmentsSection()
          }

          if (this.post.signature && this.post.signature.length > 0) {
            this.SignatureSection()
          }

          if (this.post.comments.length > 0) {
            this.CommentsSection()
          }

          this.VoteBar()
        }
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 }).alignItems(HorizontalAlign.Start)
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
        .onClick(() => { this.attachsExpanded = !this.attachsExpanded })
    }.margin({ top: 8 })
    if (this.attachsExpanded) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.post.attachs, (att: PostAttachInfo, index: number) => {
          Image(att.thumbUrl || att.attachurl).width(100).height(100).borderRadius(8)
            .objectFit(ImageFit.Cover).backgroundColor(AppColors.bgSecondary)
            .margin({ right: 6, top: 6 }).onError(() => {})
            .onClick(() => {
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
                  if (urls[i] === att.attachurl) {
                    idx = i
                    break
                  }
                }
                this.onImageClick(urls, idx)
              }
            })
        })
      }.margin({ top: 4 })
    }
  }

  @Builder
  SignatureSection() {
    Row() {
      Text(this.sigExpanded ? '收起签名' : '查看签名')
        .fontSize(12).fontColor(AppColors.textTertiary)
        .onClick(() => { this.sigExpanded = !this.sigExpanded })
    }.margin({ top: 8 })
    if (this.sigExpanded) {
      Column() {
        BBCodeContentView({
          nodes: getCachedBBNodes(this.post.signature),
          onImageClick: this.onImageClick,
          onLinkClick: this.onLinkClick,
        })
      }
      .margin({ top: 4 }).padding({ top: 4 }).border({ width: { top: 0.5 }, color: AppColors.separator })
    }
  }

  @Builder
  VoteBar() {
    Row() {
      Row() {
        Image($r('app.media.icon_thumb_up'))
          .width(16).height(16)
          .fillColor(this.votedUpPids.has(String(this.post.pid)) ? AppColors.primary : AppColors.textTertiary)
        if (this.post.score > 0 || this.votedUpPids.has(String(this.post.pid))) {
          Text(String(this.post.score))
            .fontSize(13)
            .fontColor(this.votedUpPids.has(String(this.post.pid)) ? AppColors.primary : AppColors.textSecondary)
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
          .fillColor(this.votedDownPids.has(String(this.post.pid)) ? AppColors.destructive : AppColors.textTertiary)
        if (this.post.score_2 > 0 || this.votedDownPids.has(String(this.post.pid))) {
          Text(String(this.post.score_2))
            .fontSize(13)
            .fontColor(this.votedDownPids.has(String(this.post.pid)) ? AppColors.destructive : AppColors.textSecondary)
            .margin({ left: 3 })
        }
      }
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .borderRadius(6)
      .margin({ left: 12 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onVote(this.post, -1))

      Blank().layoutWeight(1)

      Text('回复').fontSize(13).fontColor(AppColors.primary)
        .fontWeight(FontWeight.Medium)
        .onClick(() => this.onReply(this.post))
    }.width('100%').margin({ top: 8 }).alignItems(VerticalAlign.Center)
  }

  @Builder
  CommentsSection() {
    Column() {
      ForEach(this.commentsExpanded ? this.post.comments : this.post.comments.slice(0, 2), (c: PostInfo) => {
        Row() {
          Avatar({ avatar: c.avatar, uid: String(c.authorid), name: c.author, avatarSize: 24 })
            .onClick((event: ClickEvent) => {
              if (c.isanonymous) {
                appStore.showToast('这白痴匿名了,神马都看不到')
                return
              }
              const uid = String(c.authorid)
              if (uid) {
                this.onProfileClick(uid, event.screenX, event.screenY)
              }
            })

          Column() {
            AnonymousName({ author: c.author, isAnonymous: c.isanonymous, fontSize: 12, normalColor: AppColors.primary })

            BBCodeContentView({
              nodes: getCachedBBNodes(stripReplyPrefix(c.content)),
              onImageClick: this.onImageClick,
              onLinkClick: this.onLinkClick,
            }).width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 8 })
        }
        .width('100%').alignItems(VerticalAlign.Top).padding({ top: 4, bottom: 4 })
      }, (c: PostInfo) => String(c.pid))
      if (this.post.comments.length > 2) {
        Text(this.commentsExpanded ? '收起' : `查看全部 ${this.post.comments.length} 条评论`)
          .fontSize(12).fontColor(AppColors.primary).margin({ top: 4 })
          .onClick(() => { this.commentsExpanded = !this.commentsExpanded })
      }
    }
    .width('70%').alignSelf(ItemAlign.End).padding(10).backgroundColor(AppColors.bgSecondary).borderRadius(8).margin({ top: 8 })
  }
}

function stripReplyPrefix(content: string): string {
  return content.replace(
    /\[b\]Reply to \[pid=\d+,\d+,\d+\]Reply\[\/pid\] Post by \[uid=\d+\].*?\[\/uid\]\s*\(\d{4}-\d{2}-\d{2} \d{2}:\d{2}\)\[\/b\](?:<br\s*\/?>)*/i,
    ''
  ).trim()
}
