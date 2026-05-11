/**
 * 设置面板 - 从 SettingsPage 迁移, 统一 Panel 架构
 */

import router from '@ohos.router'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { AppColors, IconColors, THEME_OPTIONS, ThemeOption } from '../common/Constants'
import { ConfirmDialog } from '../common/Dialogs'
import { PanelNavBar } from '../common/PanelNavBar'

@Component
export struct SettingsPanel {
  @StorageProp('themeName') themeName: string = 'light'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  logoutDialogController?: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: '退出登录',
      message: '确定要退出登录吗？\n退出后需要重新输入账号密码登录',
      confirmLabel: '退出',
      destructive: true,
      icon: $r('app.media.icon_exit'),
      onConfirm: () => {
        appStore.clearAuth()
        router.replaceUrl({ url: 'pages/LoginPage' })
      },
      onCancel: () => {}
    }),
    autoCancel: true,
    customStyle: true
  })

  aboutToDisappear() {
    this.logoutDialogController = undefined
  }

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column() {
            Row().width('100%').height(44 + this.statusBarHeight)

            // ---- 主题选择 ----
            Column() {
              Text('主题选择').fontSize(15).fontColor(AppColors.textSecondary)
                .width('100%').padding({ left: 16, bottom: 12 })

              Scroll() {
                Row() {
                  ForEach(THEME_OPTIONS, (theme: ThemeOption) => {
                    this.ThemeCard(theme)
                  }, (theme: ThemeOption) => theme.name)
                }
                .padding({ left: 10, right: 10 })
              }
              .scrollBar(BarState.Off)
              .clip(false)
            }
            .width('100%')
            .padding({ top: 16, bottom: 16 })

            Column() {
              this.SettingRow($r('app.media.icon_block'), IconColors.block, '黑名单管理', '', () => {
                routerStore.navigateActivity(Screen.blacklist())
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              this.SettingRow($r('app.media.icon_text_fields'), IconColors.textFields, '用户备注', '', () => {
                routerStore.navigateActivity(Screen.notes())
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              this.SettingRow($r('app.media.icon_text_fields'), IconColors.textFields, '关键词屏蔽', '', () => {
                routerStore.navigateActivity(Screen.filterKeywords())
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_hand')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.hand).margin({ right: 12 })

                Text('智感握姿').fontSize(17).layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: appStore.settings.smartGrip })
                  .onChange((v: boolean) => {
                    appStore.setSmartGrip(v)
                  })
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_exit')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(AppColors.destructive).margin({ right: 12 })

                Text('退出登录').fontSize(17).fontColor(AppColors.destructive).layoutWeight(1)
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.logoutDialogController?.open()
              })
            }
            .width('92%')
            .backgroundColor(AppColors.bgTertiary)
            .borderRadius(12)
            .margin({ top: 12 })
          }
          .width('100%').alignItems(HorizontalAlign.Center).padding({ bottom: 32 })
        }
        .layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
      }
      .width('100%').height('100%').backgroundColor(AppColors.bg)

      PanelNavBar({ title: '设置' })
        .width('100%').position({ x: 0, y: 0 })
    }
    .width('100%').height('100%')
  }

  @Builder
  ThemeCard(theme: ThemeOption) {
    Column() {
      // 预览区
      Stack() {
        if (theme.name === 'system') {
          // 跟随系统：上下分半预览（上半浅色/下半深色）
          Column() {
            Stack() {
              Column() {
                Row().width(48).height(4).backgroundColor('#C08A4A').borderRadius(2)
                Row().width(36).height(4).backgroundColor('#3E2A1D').borderRadius(2).opacity(0.5).margin({ top: 8 })
                Row().width(28).height(4).backgroundColor('#3E2A1D').borderRadius(2).opacity(0.25).margin({ top: 5 })
              }
              .padding(12).alignItems(HorizontalAlign.Start).width('100%')
            }
            .width('100%').height('50%').backgroundColor('#FEFAF6')

            Stack() {
              Column() {
                Row().width(48).height(4).backgroundColor('#D4A85A').borderRadius(2)
                Row().width(36).height(4).backgroundColor('#EAE2D8').borderRadius(2).opacity(0.5).margin({ top: 8 })
                Row().width(28).height(4).backgroundColor('#EAE2D8').borderRadius(2).opacity(0.25).margin({ top: 5 })
              }
              .padding(12).alignItems(HorizontalAlign.Start).width('100%')
            }
            .width('100%').height('50%').backgroundColor('#1A1A1E')
          }
          .width('100%').height('100%')
        } else {
          Column() {
            Row().width('100%').height(3).backgroundColor(theme.primaryColor)
            Column() {
              Row().width('55%').height(5).backgroundColor(theme.textColor).borderRadius(3).opacity(0.55)
              Row().width('35%').height(5).backgroundColor(theme.textColor).borderRadius(3).opacity(0.25).margin({ top: 7 })
              Row().width('70%').height(5).backgroundColor(theme.textColor).borderRadius(3).opacity(0.35).margin({ top: 7 })
              Row().width('45%').height(5).backgroundColor(theme.textColor).borderRadius(3).opacity(0.15).margin({ top: 7 })
            }
            .padding(14).alignItems(HorizontalAlign.Start).width('100%')
          }
          .width('100%').height('100%').backgroundColor(theme.bgColor)
        }
      }
      .width('100%').height(108).borderRadius(10)
      .clip(true)
      .border({
        width: this.themeName === theme.name ? 2 : 1,
        color: this.themeName === theme.name ? AppColors.primary : AppColors.separator
      })

      // 底部：标签 + 选中状态
      Row() {
        Text(theme.label).fontSize(14).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Medium)
        Blank()
        if (this.themeName === theme.name) {
          Image($r('app.media.icon_check')).width(16).height(16).fillColor(AppColors.primary)
        } else {
          Stack().width(16).height(16).borderRadius(8).border({ width: 1.5, color: AppColors.separator })
        }
      }
      .width('100%').margin({ top: 10 })
    }
    .width(144)
    .padding(12)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(14)
    .margin({ left: 6, right: 6 })
    .onClick(() => {
      if (theme.name !== this.themeName) {
        appStore.setTheme(theme.name)
      }
    })
  }

  @Builder
  SettingRow(iconRes: Resource, iconColor: string, label: string, badge: string, action: () => void) {
    Row() {
      Stack() {
        Image(iconRes).width(17).height(17).fillColor(AppColors.white)
      }
      .width(29).height(29).borderRadius(6).backgroundColor(iconColor).margin({ right: 12 })

      Text(label).fontSize(17).layoutWeight(1)

      if (badge) {
        Text(badge).fontSize(15).fontColor(AppColors.textSecondary).margin({ right: 8 })
      }

      Text('>').fontSize(16).fontColor(AppColors.chevron)
    }
    .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
    .onClick(action)
  }
}
