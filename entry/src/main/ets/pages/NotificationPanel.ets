/**
 * 通知面板 - 从 NotificationPage 迁移, 统一 Panel 架构
 */

import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { getNotifications, clearNotifications } from '../service/NgaApi'
import type { NotificationInfo } from '../model/Notification'
import { AppColors, NOTI_TYPE_MAP } from '../common/Constants'
import { formatTime, escHtml } from '../common/Utils'
import { BreakpointType } from '../common/Constants'
import { NotificationDataSource } from '../common/LazyDataSource'

const FILTER_LABELS: string[] = ['全部', '回复', '@我', '私信']
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
  private notificationsDataSource: NotificationDataSource = new NotificationDataSource()

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

  private get filteredNotifications(): NotificationInfo[] {
    const types = FILTER_TYPES[this.activeFilter]
    if (types.length === 0) return this.notifications
    return this.notifications.filter((n: NotificationInfo) => types.includes(n.type))
  }

  private updateFilteredDataSource(): void {
    this.notificationsDataSource.replaceAll(this.filteredNotifications)
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
    Column() {
      Row() {
        Text('全部已读')
          .fontSize(14)
          .fontColor(this.clearing ? AppColors.textTertiary : AppColors.primary)
          .onClick(() => this.handleClearAll())
          .padding({ left: 8, right: 16 })
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColors.bgTertiary)
      .border({ width: { bottom: 0.5 }, color: AppColors.separator })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)

      Row() {
        ForEach(FILTER_LABELS, (label: string, index: number) => {
          Text(label)
            .fontSize(13)
            .fontColor(this.activeFilter === index ? AppColors.textPrimary : AppColors.textTertiary)
            .fontWeight(this.activeFilter === index ? FontWeight.Bold : FontWeight.Normal)
            .backgroundColor(this.activeFilter === index ? AppColors.bg : Color.Transparent)
            .borderRadius(7)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.activeFilter = index as number; this.updateFilteredDataSource() })
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
      } else if (this.filteredNotifications.length === 0) {
        Column() {
          Text('🔔').fontSize(40).opacity(0.4)
          Text('暂无通知').fontSize(15).fontColor(AppColors.textTertiary).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List() {
          LazyForEach(this.notificationsDataSource, (n: NotificationInfo) => {
            ListItem() {
              Row() {
                Text(NOTI_TYPE_MAP[n.type] ? NOTI_TYPE_MAP[n.type].icon : '📋')
                  .fontSize(20).width(32).textAlign(TextAlign.Center)
                Column() {
                  Row() {
                    Text(escHtml(n.userName)).fontSize(15).fontColor(AppColors.primary)
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
        .lanes(new BreakpointType(1, 2, 2).getValue(this.currentBreakpoint), 12)
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
  }
}
