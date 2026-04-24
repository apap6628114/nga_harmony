/**
 * 设置面板 - 从 SettingsPage 迁移, 统一 Panel 架构
 */

import router from '@ohos.router'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { AppColors, FONT_OPTIONS, DOMAIN_OPTIONS, FontOption, DomainOption } from '../common/Constants'
import { ActionSheetDialog, ActionOption, ConfirmDialog } from '../common/Dialogs'

@Component
export struct SettingsPanel {
  @State showFontSheet: boolean = false
  @State showDomainSheet: boolean = false
  @State showLogoutConfirm: boolean = false
  fontSizeDialogController?: CustomDialogController
  domainDialogController?: CustomDialogController
  logoutDialogController?: CustomDialogController

  build() {
    Column() {
      Scroll() {
        Column() {
          Column() {
            this.SettingRow('🌙', '#5856D6', '深色模式', appStore.settings.theme === 'dark' ? '开启' : '', () => {
              appStore.toggleTheme()
            })

            Divider().margin({ left: 60 }).color(AppColors.separator)

            this.SettingRow('🔤', '#FF2D55', '字号',
              FONT_OPTIONS.find((f: FontOption) => f.value === appStore.settings.fontSize)?.label ?? '中', () => {
                this.fontSizeDialogController?.open()
              })

            Divider().margin({ left: 60 }).color(AppColors.separator)

            this.SettingRow('🌐', '#5AC8FA', 'NGA 域名',
              DOMAIN_OPTIONS[appStore.settings.domainIndex]?.label ?? 'bbs.nga.cn', () => {
                this.domainDialogController?.open()
              })
          }
          .width('92%')
          .backgroundColor(AppColors.bgTertiary)
          .borderRadius(12)
          .margin({ top: 16 })

          Column() {
            this.SettingRow('🚫', '#8E8E93', '黑名单管理', '', () => {
              routerStore.navigateActivity(Screen.blacklist())
            })

            Divider().margin({ left: 60 }).color(AppColors.separator)

            Row() {
              Stack() {
                Text('🚪').fontSize(17).fontColor(Color.White)
              }
              .width(29).height(29).borderRadius(6).backgroundColor('#FF3B30').margin({ right: 12 })

              Text('退出登录').fontSize(17).fontColor('#FF3B30').layoutWeight(1)
            }
            .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.logoutDialogController?.open()
            })
          }
          .width('92%')
          .backgroundColor(AppColors.bgTertiary)
          .borderRadius(12)
          .margin({ top: 16 })
        }
        .width('100%').alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
    .bindContentCover(this.fontSizeDialogController !== undefined, this.FontSizeDialogBuilder())
    .bindContentCover(this.domainDialogController !== undefined, this.DomainDialogBuilder())
    .bindContentCover(this.logoutDialogController !== undefined, this.LogoutDialogBuilder())
  }

  @Builder
  FontSizeDialogBuilder() {
    ActionSheetDialog({
      title: '选择字号',
      options: FONT_OPTIONS as ActionOption[],
      selected: appStore.settings.fontSize,
      onSelect: (value: number) => {
        appStore.setFontSize(value)
      },
      onCancel: () => {}
    })
  }

  @Builder
  DomainDialogBuilder() {
    ActionSheetDialog({
      title: '选择域名',
      options: DOMAIN_OPTIONS as ActionOption[],
      selected: appStore.settings.domainIndex,
      onSelect: (value: number) => {
        appStore.setDomainIndex(value)
      },
      onCancel: () => {}
    })
  }

  @Builder
  LogoutDialogBuilder() {
    ConfirmDialog({
      title: '退出登录',
      message: '确定要退出登录吗？',
      confirmLabel: '退出',
      destructive: true,
      onConfirm: () => {
        appStore.clearAuth()
        router.replaceUrl({ url: 'pages/LoginPage' })
      },
      onCancel: () => {}
    })
  }

  @Builder
  SettingRow(icon: string, iconColor: string, label: string, badge: string, action: () => void) {
    Row() {
      Stack() {
        Text(icon).fontSize(17).fontColor(Color.White)
      }
      .width(29).height(29).borderRadius(6).backgroundColor(iconColor).margin({ right: 12 })

      Text(label).fontSize(17).layoutWeight(1)

      if (badge) {
        Text(badge).fontSize(15).fontColor(AppColors.textSecondary).margin({ right: 8 })
      }

      Text('>').fontSize(16).fontColor('#C7C7CC')
    }
    .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
    .onClick(action)
  }
}
