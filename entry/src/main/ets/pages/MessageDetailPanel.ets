/**
 * 私信详情面板 - 从 MessageDetailPage 迁移, 统一 Panel 架构
 */

import { appStore } from '../store/AppStore'
import { getMessageDetail, sendMessage } from '../service/NgaApi'
import type { MessageArticle } from '../model/Message'
import { AppColors } from '../common/Constants'
import { formatTime, escHtml } from '../common/Utils'
import { Avatar } from '../common/Avatar'
import { MessageArticleDataSource } from '../common/LazyDataSource'

@Component
export struct MessageDetailPanel {
  @Prop @Watch('onMidChanged') mid: string = ''
  @State messages: MessageArticle[] = []
  @State title: string = '私信详情'
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State replyText: string = ''
  @State sending: boolean = false
  @StorageProp('navBarHeight') navBarHeight: number = 0

  private scroller: Scroller = new Scroller()
  private messagesDataSource: MessageArticleDataSource = new MessageArticleDataSource()

  aboutToAppear(): void {
    this.loadMessages()
  }

  private onMidChanged(): void {
    this.messages = []
    this.messagesDataSource.clear()
    this.hasError = false
    this.loadMessages()
  }

  private async loadMessages(): Promise<void> {
    if (!this.mid) return
    this.isLoading = true
    this.hasError = false
    try {
      const result = await getMessageDetail(appStore.auth.token, this.mid, '1')
      if (result.ok && result.data) {
        this.messages = result.data.messageEntryList
        this.messagesDataSource.replaceAll(this.messages)
        this.title = result.data.title || '私信详情'
        setTimeout(() => {
          this.scroller.scrollEdge(Edge.Bottom)
        }, 300)
      } else {
        this.hasError = true
      }
    } catch (e) {
      this.hasError = true
    }
    this.isLoading = false
  }

  private async handleReply(): Promise<void> {
    const content = this.replyText.trim()
    if (!content || !this.mid || this.sending) return

    this.sending = true
    try {
      const result = await sendMessage(appStore.auth.token, '', this.mid, '', content)
      if (result.ok) {
        this.replyText = ''
        appStore.showToast('回复成功')
        this.loadMessages()
      } else {
        appStore.showToast(result.error || '回复失败')
      }
    } catch (e) {
      appStore.showToast('回复失败')
    }
    this.sending = false
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(28).height(28).color(AppColors.textTertiary)
          Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.hasError) {
        Column() {
          Text('加载失败').fontSize(14).fontColor(AppColors.textTertiary).margin({ bottom: 12 })
          Button('重试').fontSize(14).fontColor(AppColors.primary).backgroundColor(AppColors.bgSecondary).borderRadius(10)
            .onClick(() => this.loadMessages())
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.messages.length === 0) {
        Column() {
          Image($r('app.media.icon_chat_bubble')).width(40).height(40).opacity(0.4)
          Text('暂无消息').fontSize(15).fontColor(AppColors.textTertiary).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        if (this.title && this.title !== '私信详情') {
          Text(escHtml(this.title))
            .fontSize(17).fontWeight(FontWeight.Bold).width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 8 })
            .backgroundColor(AppColors.bgTertiary)
            .border({ width: { bottom: 0.5 }, color: AppColors.separator })
        }

        List({ scroller: this.scroller }) {
          LazyForEach(this.messagesDataSource, (msg: MessageArticle) => {
            ListItem() {
              Row() {
                Avatar({ name: msg.author || msg.from || '未知', avatarSize: 36 })
                Column() {
                  Row() {
                    Text(escHtml(msg.author || msg.from || '未知'))
                      .fontSize(14).fontColor(AppColors.primary).fontWeight(FontWeight.Medium)
                    Text(formatTime(Number(msg.time))).fontSize(12).fontColor(AppColors.textTertiary).margin({ left: 8 })
                  }
                  if (msg.formated_html_data) {
                    RichText(msg.formated_html_data).width('100%').margin({ top: 4 })
                  } else {
                    Text(escHtml(msg.content)).fontSize(15).fontColor(AppColors.textPrimary)
                      .margin({ top: 4 }).lineHeight(22)
                  }
                }
                .layoutWeight(1).margin({ left: 10 }).alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 }).alignItems(VerticalAlign.Top)
            }
          }, (msg: MessageArticle) => String(msg.time) + String(msg.from))
        }
        .width('100%').layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
      }

      if (!this.isLoading && !this.hasError) {
        Row() {
          TextInput({ text: this.replyText, placeholder: '写回复...' })
            .layoutWeight(1).fontSize(15).borderRadius(12)
            .backgroundColor(AppColors.bgSecondary).height(40).padding({ left: 12, right: 12 })
            .onChange((value: string) => { this.replyText = value })
            .onSubmit(() => this.handleReply())
          Button('发送')
            .fontSize(14).fontColor(Color.White).backgroundColor(AppColors.primary)
            .borderRadius(12).height(40).padding({ left: 16, right: 16 }).margin({ left: 8 })
            .enabled(!this.sending && this.replyText.trim().length > 0)
            .onClick(() => this.handleReply())
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 + this.navBarHeight })
        .backgroundColor(AppColors.bgTertiary)
        .border({ width: { top: 0.5 }, color: AppColors.separator })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
  }
}
