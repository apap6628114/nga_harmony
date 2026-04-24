/**
 * 浏览历史面板 - 从 BrowseHistoryPage 迁移, 统一 Panel 架构
 */

import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { AppColors } from '../common/Constants'
import { ConfirmDialog } from '../common/Dialogs'
import { escHtml, formatTime } from '../common/Utils'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { HistoryItemDataSource } from '../common/LazyDataSource'

class HistoryItem {
  tid: string = ''
  subject: string = ''
  author: string = ''
  replies: number = 0
  ts: number = 0
  board: string = ''
}

@Component
export struct BrowseHistoryPanel {
  @State items: HistoryItem[] = []
  @State showClearConfirm: boolean = false
  clearDialogController?: CustomDialogController
  private historyDataSource: HistoryItemDataSource = new HistoryItemDataSource()

  aboutToAppear(): void {
    this.loadHistory()
  }

  private async loadHistory(): Promise<void> {
    try {
      const ctx = getContext(this) as Context
      const pref = await preferences.getPreferences(ctx, 'nga_browse_history')
      const raw = (await pref.get('items', '[]')) as string
      this.items = JSON.parse(raw) as HistoryItem[]
      this.historyDataSource.replaceAll(this.items as object[])
    } catch (e) {
      this.items = []
    }
  }

  private async removeItem(tid: string): Promise<void> {
    this.items = this.items.filter((item: HistoryItem) => item.tid !== tid)
    this.historyDataSource.replaceAll(this.items as object[])
    await this.persist()
  }

  private async clearAll(): Promise<void> {
    this.items = []
    this.historyDataSource.clear()
    await this.persist()
  }

  private async persist(): Promise<void> {
    try {
      const ctx = getContext(this) as Context
      const pref = await preferences.getPreferences(ctx, 'nga_browse_history')
      await pref.put('items', JSON.stringify(this.items))
      await pref.flush()
    } catch (e) {
    }
  }

  build() {
    Column() {
      if (this.items.length > 0) {
        Row() {
          Text('清空')
            .fontSize(14).fontColor(AppColors.primary)
            .margin({ right: 16 })
            .onClick(() => { this.clearDialogController?.open() })
        }
        .width('100%').height(44).backgroundColor(AppColors.bgTertiary)
        .border({ width: { bottom: 0.5 }, color: AppColors.separator })
        .alignItems(VerticalAlign.Center).justifyContent(FlexAlign.End)
      }

      if (this.items.length === 0) {
        Column() {
          Text('🕐').fontSize(40).opacity(0.4).margin({ bottom: 12 })
          Text('暂无浏览记录').fontSize(15).fontColor(AppColors.textTertiary)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List() {
          LazyForEach(this.historyDataSource, (itemObj: object) => {
            ListItem() {
              Row() {
                Column() {
                  Text(escHtml((itemObj as HistoryItem).subject))
                    .fontSize(15).fontColor(AppColors.textPrimary).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Row() {
                    if ((itemObj as HistoryItem).board) {
                      Text(escHtml((itemObj as HistoryItem).board))
                        .fontSize(12).fontColor(AppColors.textTertiary).margin({ right: 4 })
                    }
                    Text(`${escHtml((itemObj as HistoryItem).author)} · ${formatTime((itemObj as HistoryItem).ts / 1000)}`)
                      .fontSize(12).fontColor(AppColors.textTertiary)
                    Text(`💬 ${(itemObj as HistoryItem).replies}`)
                      .fontSize(12).fontColor(AppColors.textTertiary).margin({ left: 8 })
                  }
                  .margin({ top: 6 })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                Text('✕').fontSize(16).fontColor(AppColors.textTertiary).padding(8)
                  .onClick(() => this.removeItem((itemObj as HistoryItem).tid))
              }
              .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                routerStore.navigateActivity(Screen.thread((itemObj as HistoryItem).tid))
              })
            }
          }, (itemObj: object) => (itemObj as HistoryItem).tid)
        }
        .layoutWeight(1).divider({ strokeWidth: 0.5, color: AppColors.separator })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
    .bindContentCover(this.clearDialogController !== undefined, this.ClearDialogBuilder())
  }

  @Builder
  ClearDialogBuilder() {
    ConfirmDialog({
      title: '清空浏览记录',
      message: '确定清空所有浏览记录？此操作不可撤销。',
      confirmLabel: '清空',
      destructive: true,
      onConfirm: () => {
        this.clearAll()
        appStore.showToast('已清空浏览记录')
      },
      onCancel: () => {}
    })
  }
}
