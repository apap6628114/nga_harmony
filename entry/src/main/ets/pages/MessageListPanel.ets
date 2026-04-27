/**
 * 私信列表面板 - 从 MessageListPage 迁移, 统一 Panel 架构
 */

import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { getMessageList, sendMessage, MessageListResult, MessageSendResult } from '../service/NgaApi'
import type { MessageThreadInfo } from '../model/Message'
import { AppColors, BreakpointType } from '../common/Constants'
import { formatTime, escHtml } from '../common/Utils'
import { Avatar } from '../common/Avatar'
import { PanelNavBar } from '../common/PanelNavBar'
import { MessageThreadDataSource } from '../common/LazyDataSource'

@Component
export struct MessageListPanel {
  @Prop composeToInit: string = ''
  @State threads: MessageThreadInfo[] = []
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State showCompose: boolean = false
  @State composeTo: string = ''
  @State composeSubject: string = ''
  @State composeContent: string = ''
  @State sending: boolean = false
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0
  private threadsDataSource: MessageThreadDataSource = new MessageThreadDataSource()

  aboutToAppear(): void {
    if (this.composeToInit.length > 0) {
      this.composeTo = this.composeToInit
      this.showCompose = true
    }
    this.loadMessages()
  }

  private async loadMessages(): Promise<void> {
    this.isLoading = true
    this.hasError = false
    try {
      const result: MessageListResult = await getMessageList(appStore.auth.token, '1')
      if (result.ok && result.data) {
        this.threads = result.data.messageEntryList
        this.threadsDataSource.replaceAll(this.threads)
      } else {
        this.hasError = true
      }
    } catch (e) {
      this.hasError = true
    }
    this.isLoading = false
  }

  private async handleSend(): Promise<void> {
    const to = this.composeTo.trim()
    const subject = this.composeSubject.trim()
    const content = this.composeContent.trim()
    if (!to || !subject || !content) return

    this.sending = true
    try {
      const result: MessageSendResult = await sendMessage(appStore.auth.token, to, '', subject, content)
      if (result.ok) {
        appStore.showToast('发送成功')
        this.showCompose = false
        this.composeTo = ''
        this.composeSubject = ''
        this.composeContent = ''
        this.loadMessages()
      } else {
        appStore.showToast(result.error || '发送失败')
      }
    } catch (e) {
      appStore.showToast('发送失败')
    }
    this.sending = false
  }

  build() {
    Column() {
      PanelNavBar({ title: '私信', rightIcon: $r('app.media.icon_compose'), onRightClick: (): void => { this.showCompose = true } })

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
      } else if (this.threads.length === 0) {
        Column() {
          Image($r('app.media.icon_mail')).width(40).height(40).opacity(0.4)
          Text('暂无私信').fontSize(15).fontColor(AppColors.textTertiary).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List() {
          LazyForEach(this.threadsDataSource, (thread: MessageThreadInfo) => {
            ListItem() {
              Row() {
                Avatar({ name: thread.last_from_username || thread.from_username, avatarSize: 44 })
                Column() {
                  Text(escHtml(thread.subject)).fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${escHtml(thread.last_from_username || thread.from_username)} · ${thread.posts}条消息 · ${formatTime(Number(thread.lasttime))}`)
                    .fontSize(13).fontColor(AppColors.textTertiary).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
                }.layoutWeight(1).margin({ left: 12 }).alignItems(HorizontalAlign.Start)
                Text('›').fontSize(18).fontColor(AppColors.textTertiary)
              }
              .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                routerStore.navigateActivity(Screen.messageDetail(String(thread.mid)))
              })
            }
          }, (thread: MessageThreadInfo) => String(thread.mid))
        }
        .width('100%').layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
        .lanes(new BreakpointType(1, 2, 2).getValue(this.currentBreakpoint), 12)
      }



      if (this.showCompose) {
        Column() {
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
        .backgroundColor('#40000000')
        .onClick(() => { this.showCompose = false })

        Column() {
          Divider().width(36).height(4).borderRadius(2).color('#D1D1D6').margin({ top: 8, bottom: 12 })
          Row() {
            Text('写私信').fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
            Text('✕').fontSize(20).fontColor(AppColors.textTertiary)
              .onClick(() => { this.showCompose = false })
          }.width('100%').padding({ left: 16, right: 16 })

          TextInput({ text: this.composeTo, placeholder: '收件人（用户名）' })
            .width('92%').height(44).fontSize(15).borderRadius(12)
            .backgroundColor(AppColors.bgSecondary).margin({ top: 12 })
            .onChange((value: string) => { this.composeTo = value })

          TextInput({ text: this.composeSubject, placeholder: '主题' })
            .width('92%').height(44).fontSize(15).borderRadius(12)
            .backgroundColor(AppColors.bgSecondary).margin({ top: 8 })
            .onChange((value: string) => { this.composeSubject = value })

          TextArea({ text: this.composeContent, placeholder: '内容' })
            .width('92%').height(100).fontSize(15).borderRadius(12)
            .backgroundColor(AppColors.bgSecondary).margin({ top: 8 })
            .onChange((value: string) => { this.composeContent = value })

          Button(this.sending ? '发送中...' : '发送')
            .width('92%').height(44).fontSize(16).fontColor(Color.White)
            .backgroundColor(AppColors.primary).borderRadius(12).margin({ top: 12, bottom: 20 })
            .enabled(!this.sending && this.composeTo.trim().length > 0 &&
              this.composeSubject.trim().length > 0 && this.composeContent.trim().length > 0)
            .onClick(() => this.handleSend())
        }
        .width('100%').backgroundColor(AppColors.bg)
        .borderRadius({ topLeft: 14, topRight: 14 }).alignItems(HorizontalAlign.Center)
        .padding({ bottom: this.navBarHeight })
        .position({ x: 0, y: '40%' })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
  }
}
