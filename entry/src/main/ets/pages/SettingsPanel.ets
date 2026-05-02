/**
 * 设置面板 - 从 SettingsPage 迁移, 统一 Panel 架构
 */

import router from '@ohos.router'
import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { AppColors, IconColors, FONT_OPTIONS, DOMAIN_OPTIONS, THEME_OPTIONS, FontOption, DomainOption, ThemeOption } from '../common/Constants'
import { ActionSheetDialog, ActionOption, ConfirmDialog } from '../common/Dialogs'

@Component
export struct SettingsPanel {
  @StorageProp('themeName') themeName: string = 'light'

  fontSizeDialogController?: CustomDialogController = new CustomDialogController({
    builder: ActionSheetDialog({
      title: '选择字号',
      options: FONT_OPTIONS as ActionOption[],
      selected: appStore.settings.fontSize,
      getLabelFontSize: (value: number): number => value,
      onSelect: (value: number) => {
        appStore.setFontSize(value)
      },
      onCancel: () => {}
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Bottom,
    offset: { dx: 0, dy: 0 }
  })

  domainDialogController?: CustomDialogController = new CustomDialogController({
    builder: ActionSheetDialog({
      title: '选择域名',
      options: DOMAIN_OPTIONS as ActionOption[],
      selected: appStore.settings.domainIndex,
      onSelect: (value: number) => {
        appStore.setDomainIndex(value)
      },
      onCancel: () => {}
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Bottom,
    offset: { dx: 0, dy: 0 }
  })

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
    this.fontSizeDialogController = undefined
    this.domainDialogController = undefined
    this.logoutDialogController = undefined
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ---- 主题选择 ----
          Column() {
            Text('主题选择').fontSize(15).fontColor(AppColors.textSecondary)
              .width('100%').padding({ left: 16, bottom: 12 })

            Row() {
              ForEach(THEME_OPTIONS, (theme: ThemeOption) => {
                this.ThemeCard(theme)
              }, (theme: ThemeOption) => theme.name)
            }
            .width('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Top)
          }
          .width('92%')
          .backgroundColor(AppColors.bgTertiary)
          .borderRadius(12)
          .padding({ top: 16, bottom: 16 })

          // ---- 其他设置 ----
          Column() {
            this.SettingRow($r('app.media.icon_text_fields'), IconColors.textFields, '字号',
              FONT_OPTIONS.find((f: FontOption) => f.value === appStore.settings.fontSize)?.label ?? '中', () => {
                this.fontSizeDialogController?.open()
              })

            Divider().margin({ left: 60 }).color(AppColors.separator)

            this.SettingRow($r('app.media.icon_globe'), IconColors.globe, 'NGA 域名',
              DOMAIN_OPTIONS[appStore.settings.domainIndex]?.label ?? 'bbs.nga.cn', () => {
                this.domainDialogController?.open()
              })
          }
          .width('92%')
          .backgroundColor(AppColors.bgTertiary)
          .borderRadius(12)
          .margin({ top: 16 })

          Column() {
            this.SettingRow($r('app.media.icon_block'), IconColors.block, '黑名单管理', '', () => {
              routerStore.navigateActivity(Screen.blacklist())
            })

            Divider().margin({ left: 60 }).color(AppColors.separator)

            this.SettingRow($r('app.media.icon_text_fields'), IconColors.textFields, '关键词屏蔽', '', () => {
              routerStore.navigateActivity(Screen.filterKeywords())
            })

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
          .margin({ top: 16 })
        }
        .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 12, bottom: 32 })
      }
      .layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }
    .width('100%').height('100%').backgroundColor(AppColors.bg)
  }

  @Builder
  ThemeCard(theme: ThemeOption) {
    Column() {
      // 色块预览
      Row() {
        Stack().width(28).height(28).borderRadius(8).backgroundColor(theme.primaryColor)
        Stack().width(28).height(28).borderRadius(8).backgroundColor(theme.bgColor)
          .border({ width: 1, color: AppColors.separator }).margin({ left: 6 })
      }
      .width('100%').justifyContent(FlexAlign.Center).padding({ top: 16, bottom: 8 })

      Text(theme.label).fontSize(15).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Medium)

      // 选中指示
      if (this.themeName === theme.name) {
        Row() {
          Image($r('app.media.icon_check')).width(14).height(14).fillColor(AppColors.white)
        }
        .width(22).height(22).borderRadius(11).backgroundColor(AppColors.primary)
        .margin({ top: 8 })
      } else {
        Stack().width(22).height(22).borderRadius(11).border({ width: 2, color: AppColors.separator })
          .margin({ top: 8 })
      }
    }
    .width('44%')
    .backgroundColor(this.themeName === theme.name ? AppColors.bgSecondary : AppColors.white)
    .borderRadius(12)
    .borderWidth(this.themeName === theme.name ? 2 : 1)
    .borderColor(this.themeName === theme.name ? AppColors.primary : AppColors.separator)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 16 })
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
