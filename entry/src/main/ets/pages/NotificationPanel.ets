/**
 * 通知面板 - 从 NotificationPage 迁移, 统一 Panel 架构
 */

import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { getNotifications, clearNotifications } from '../service/NgaApi'
import type { NotificationInfo } from '../model/Notification'
import { AppColors, NOTI_TYPE_MAP, getNotiIcon } from '../common/Constants'
import { formatTime, escHtml, unescapeHtml } from '../common/Utils'
import { BreakpointType } from '../common/Constants'
import { PanelNavBar } from '../common/PanelNavBar'
import { NotificationDataSource } from '../common/LazyDataSource'

interface FilterMode {
  key: number
  label: string
}

const FILTER_MODES: FilterMode[] = [
  { key: 0, label: '全部' },
  { key: 1, label: '回复' },
  { key: 2, label: '@我' },
  { key: 3, label: '私信' }
]
const FILTER_TYPES: number[][] = [[], [1, 2, 3, 4], [7, 8], [10, 11]]

@Component
export struct NotificationPanel {
  @State notifications: NotificationInfo[] = []
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State errorMsg: string = ''
  @State activeFilter: number = 0
  @State clearing: boolean = false
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  private notificationsDataSource: NotificationDataSource = new NotificationDataSource()
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadNotifications()
  }

  private async loadNotifications(): Promise<void> {
    this.isLoading = true
    this.hasError = false
    try {
      const result = await getNotifications(appStore.auth.token)
      if (result.ok) {
        this.notifications = result.data as NotificationInfo[]
        this.updateFilteredDataSource()
      } else {
        this.hasError = true
        this.errorMsg = result.error || '加载失败'
      }
    } catch (e) {
      this.hasError = true
      this.errorMsg = (e as Error).message || '加载失败'
    }
    this.isLoading = false
  }

  private getFilteredNotifications(): NotificationInfo[] {
    const list = this.notifications
    if (!list) return []
    const types = FILTER_TYPES[this.activeFilter]
    if (types.length === 0) return list
    return list.filter((n: NotificationInfo) => types.includes(n.type))
  }

  private updateFilteredDataSource(): void {
    this.notificationsDataSource.replaceAll(this.getFilteredNotifications())
  }

  private async handleClearAll(): Promise<void> {
    if (this.clearing) return
    this.clearing = true
    try {
      await clearNotifications(appStore.auth.token)
      this.notifications = []
      this.notificationsDataSource.clear()
    } catch (e) {
      appStore.showToast('清除失败')
    }
    this.clearing = false
  }

  private handleNotificationClick(n: NotificationInfo): void {
    const info = NOTI_TYPE_MAP[n.type]
    if (info && info.category === 'message') {
      routerStore.navigateActivity(Screen.messages())
    } else {
      routerStore.navigateActivity(Screen.topicList(n.userName + '的帖子', -1, n.userId))
    }
  }

  build() {
    Stack() {
      Column() {
        Row().width('100%').height(44 + this.statusBarHeight)
        Row() {
          ForEach(FILTER_MODES, (mode: FilterMode) => {
            Text(mode.label)
              .fontSize(13)
              .fontColor(this.activeFilter === mode.key ? AppColors.textPrimary : AppColors.textTertiary)
              .fontWeight(this.activeFilter === mode.key ? FontWeight.Bold : FontWeight.Normal)
              .backgroundColor(this.activeFilter === mode.key ? AppColors.bg : Color.Transparent)
              .borderRadius(7)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                if (this.activeFilter !== mode.key) {
                  this.activeFilter = mode.key
                  this.updateFilteredDataSource()
                }
              })
          })
        }
        .width('92%')
        .margin({ top: 8, bottom: 4 })
        .padding(3)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(10)

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(28).height(28).color(AppColors.textTertiary)
            Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 8 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.hasError) {
          Column() {
            Text(this.errorMsg).fontSize(14).fontColor(AppColors.textTertiary).margin({ bottom: 12 })
            Button('重试').fontSize(14).fontColor(AppColors.primary).backgroundColor(AppColors.bgSecondary).borderRadius(10)
              .onClick(() => this.loadNotifications())
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.notifications.length === 0) {
          Column() {
            Image($r('app.media.icon_bell')).width(40).height(40).opacity(0.4)
            Text('暂无通知').fontSize(15).fontColor(AppColors.textTertiary).margin({ top: 8 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ scroller: this.scroller }) {
            LazyForEach(this.notificationsDataSource, (n: NotificationInfo) => {
              ListItem() {
                Row() {
                  Image(getNotiIcon(n.type)).width(20).height(20).fillColor(AppColors.textSecondary)
                  Column() {
                    Row() {
                      Text(unescapeHtml(n.userName)).fontSize(15).fontColor(AppColors.primary)
                      Text(` ${escHtml(NOTI_TYPE_MAP[n.type] ? NOTI_TYPE_MAP[n.type].label : '通知')}`)
                        .fontSize(15).fontColor(AppColors.textSecondary)
                    }.width('100%')
                    Text(formatTime(Number(n.timeStamp))).fontSize(12).fontColor(AppColors.textTertiary).margin({ top: 2 })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 8 })
                }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 }).alignItems(VerticalAlign.Center)
                .onClick(() => this.handleNotificationClick(n))
              }
            }, (n: NotificationInfo) => String(n.timeStamp) + String(n.userId))
          }
          .width('100%').layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: AppColors.separator })
          .lanes(new BreakpointType(1, 1, 1).getValue(this.currentBreakpoint), 12)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%').height('100%')

      PanelNavBar({ title: '通知', rightLabel: '全部已读', rightLabelColor: this.clearing ? AppColors.textTertiary : AppColors.primary, onRightClick: (): void => { this.handleClearAll() } })
        .width('100%').position({ x: 0, y: 0 })
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
  }
}
