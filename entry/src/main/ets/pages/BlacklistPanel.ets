/**
 * 黑名单管理面板 - 从 BlacklistPage 迁移, 统一 Panel 架构
 */

import { appStore } from '../store/AppStore'
import type { BlacklistEntry } from '../store/AppStore'
import { ConfirmDialog } from '../common/Dialogs'
import { AppColors } from '../common/Constants'
import { escHtml } from '../common/Utils'
import { BlacklistDataSource } from '../common/LazyDataSource'

@Component
export struct BlacklistPanel {
  @State showAddDialog: boolean = false
  @State addUid: string = ''
  @State removeTarget: BlacklistEntry | null = null

  private confirmDialogController?: CustomDialogController
  private blacklistDataSource: BlacklistDataSource = new BlacklistDataSource()

  aboutToAppear(): void {
    this.blacklistDataSource.replaceAll(appStore.settings.blacklist)
  }

  build() {
    Column() {
      Row() {
        Text('+ 添加')
          .fontSize(15)
          .fontColor(AppColors.primary)
          .margin({ right: 16 })
          .onClick(() => { this.showAddDialog = true })
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColors.bgTertiary)
      .border({ width: { bottom: 0.5 }, color: AppColors.separator })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)

      if (appStore.settings.blacklist.length === 0) {
        Column() {
          Text('👤').fontSize(36).opacity(0.4)
          Text('黑名单为空').fontSize(15).fontColor(AppColors.textTertiary).margin({ top: 8 })
          Text('点击右上角添加').fontSize(13).fontColor(AppColors.textTertiary).margin({ top: 4 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List() {
          LazyForEach(this.blacklistDataSource, (entry: BlacklistEntry) => {
            ListItem() {
              Row() {
                Stack() {
                  Text('👤').fontSize(20).fontColor(AppColors.textTertiary)
                }
                .width(40).height(40).borderRadius(20).backgroundColor(AppColors.bgSecondary)

                Column() {
                  Text(escHtml(entry.nickName)).fontSize(15).fontColor(AppColors.textPrimary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`UID: ${escHtml(entry.userId)}`).fontSize(13).fontColor(AppColors.textTertiary).margin({ top: 2 })
                }
                .layoutWeight(1).margin({ left: 12 }).alignItems(HorizontalAlign.Start)

                Text('🗑').fontSize(18).fontColor(AppColors.destructive).padding(8)
                  .onClick(() => {
                    this.removeTarget = entry
                    this.confirmDialogController?.open()
                  })
              }
              .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 }).alignItems(VerticalAlign.Center)
            }
          }, (entry: BlacklistEntry) => entry.userId)
        }
        .width('100%').layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppColors.separator })
        .margin({ top: 16 })
      }

      if (this.showAddDialog) {
        Column() {
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
        .backgroundColor('#40000000')
        .onClick(() => { this.showAddDialog = false })

        Column() {
          Text('添加黑名单').fontSize(17).fontWeight(FontWeight.Bold).margin({ top: 24 })
          Text('输入用户 UID').fontSize(13).fontColor(AppColors.textSecondary).margin({ top: 4 })

          TextInput({ text: this.addUid, placeholder: '输入 UID' })
            .width('80%').height(44).fontSize(15).borderRadius(8)
            .backgroundColor(AppColors.bgSecondary).margin({ top: 16 })
            .onChange((value: string) => { this.addUid = value })
            .onSubmit(() => {
              if (this.addUid.trim()) {
                appStore.addBlacklist({ userId: this.addUid.trim(), nickName: `User${this.addUid.trim()}` })
                this.blacklistDataSource.replaceAll(appStore.settings.blacklist)
                this.addUid = ''
                this.showAddDialog = false
              }
            })

          Divider().color(AppColors.separator).margin({ top: 16 })

          Row() {
            Text('取消').fontSize(17).fontColor(AppColors.primary).layoutWeight(1)
              .textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
              .onClick(() => { this.showAddDialog = false })
            Divider().vertical(true).height(20).color(AppColors.separator)
            Text('确定').fontSize(17).fontColor(AppColors.primary).fontWeight(FontWeight.Bold)
              .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
              .onClick(() => {
                if (this.addUid.trim()) {
                  appStore.addBlacklist({ userId: this.addUid.trim(), nickName: `User${this.addUid.trim()}` })
                  this.blacklistDataSource.replaceAll(appStore.settings.blacklist)
                  this.addUid = ''
                  this.showAddDialog = false
                }
              })
          }
        }
        .width(300).backgroundColor(AppColors.bg).borderRadius(14).alignItems(HorizontalAlign.Center)
        .position({ x: '50%', y: '50%' }).translate({ x: '-50%', y: '-50%' })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
    .bindContentCover(this.removeTarget !== null, this.ConfirmRemoveBuilder())
  }

  @Builder
  ConfirmRemoveBuilder() {
    Column() {
      if (this.removeTarget) {
        ConfirmDialog({
          title: '移除黑名单',
          message: `确定要将 ${this.removeTarget.nickName} 从黑名单中移除吗？`,
          confirmLabel: '移除',
          destructive: true,
          onConfirm: () => {
            if (this.removeTarget) {
              appStore.removeBlacklist(this.removeTarget.userId)
              this.blacklistDataSource.replaceAll(appStore.settings.blacklist)
              this.removeTarget = null
            }
          },
          onCancel: () => {
            this.removeTarget = null
          }
        })
      }
    }
  }
}
