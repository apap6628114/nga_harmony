/**
 * 设置面板 - 从 SettingsPage 迁移, 统一 Panel 架构
 */


import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { AppColors, IconColors, ImageLoadStrategy, ThreadNavMode, THEME_OPTIONS, ThemeOption } from '../common/Constants'
import { ConfirmDialog, ActionSheetDialog, ActionOption } from '../common/Dialogs'
import { PanelNavBar } from '../common/PanelNavBar'
import { picker, fileIo, storageStatistics } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common, contextConstant } from '@kit.AbilityKit'

@Component
export struct SettingsPanel {
  @StorageProp('themeName') themeName: string = 'light'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @State cacheSizeText: string = ''
  @State clearingCache: boolean = false
  @State imageStrategyBadge: string = '始终加载'
  @State threadNavBadge: string = '无缝加载'
  @State prefetchPageBadge: string = '3 页'

  clearCacheDialogController?: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: '清除缓存',
      message: '确定要清除所有缓存吗？\n清除后图片等资源需要重新加载',
      confirmLabel: '清除',
      destructive: true,
      icon: $r('app.media.icon_delete'),
      onConfirm: () => {
        this.clearCache()
      },
      onCancel: () => {}
    }),
    autoCancel: true,
    customStyle: true
  })

  imageStrategyDialogController?: CustomDialogController
  threadNavDialogController?: CustomDialogController
  prefetchPageDialogController?: CustomDialogController
  logoutDialogController?: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: '退出登录',
      message: '确定要退出登录吗？\n退出后需要重新输入账号密码登录',
      confirmLabel: '退出',
      destructive: true,
      icon: $r('app.media.icon_exit'),
      onConfirm: () => {
        appStore.clearAuth()
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' })
      },
      onCancel: () => {}
    }),
    autoCancel: true,
    customStyle: true
  })

  aboutToAppear(): void {
    this.refreshCacheSize()
    this.imageStrategyBadge = this.imageStrategyLabel(appStore.settings.imageLoadStrategy)
    this.threadNavBadge = this.threadNavLabel(appStore.settings.threadNavMode)
    this.prefetchPageBadge = this.prefetchPageLabel(appStore.settings.prefetchPageCount)
  }

  aboutToDisappear() {
    this.clearCacheDialogController = undefined
    this.logoutDialogController = undefined
    this.imageStrategyDialogController = undefined
    this.threadNavDialogController = undefined
    this.prefetchPageDialogController = undefined
  }

  private formatSize(bytes: number): string {
    if (bytes < 1024) {
      return bytes + ' B'
    }
    const kb: number = bytes / 1024
    if (kb < 1024) {
      return kb.toFixed(1) + ' KB'
    }
    const mb: number = kb / 1024
    if (mb < 1024) {
      return mb.toFixed(1) + ' MB'
    }
    const gb: number = mb / 1024
    return gb.toFixed(2) + ' GB'
  }

  private refreshCacheSize(): void {
    storageStatistics.getCurrentBundleStats((err: BusinessError, bundleStats: storageStatistics.BundleStats) => {
      if (!err) {
        this.cacheSizeText = this.formatSize(bundleStats.cacheSize)
      } else {
        this.cacheSizeText = '未知'
      }
    })
  }

  private async clearCache(): Promise<void> {
    if (this.clearingCache) {
      return
    }
    this.clearingCache = true
    let context: common.UIAbilityContext | null = null
    let originArea: number = 0
    let appContext: common.Context | null = null
    let originAppArea: number = 0
    try {
      context = this.getUIContext().getHostContext() as common.UIAbilityContext
      originArea = context.area
      const dirs: string[] = []

      context.area = contextConstant.AreaMode.EL1
      dirs.push(context.cacheDir)
      context.area = contextConstant.AreaMode.EL2
      dirs.push(context.cacheDir)

      appContext = context.getApplicationContext()
      originAppArea = appContext.area
      appContext.area = contextConstant.AreaMode.EL1
      dirs.push(appContext.cacheDir)
      appContext.area = contextConstant.AreaMode.EL2
      dirs.push(appContext.cacheDir)

      for (let i = 0; i < dirs.length; i++) {
        if (fileIo.accessSync(dirs[i])) {
          try {
            fileIo.rmdirSync(dirs[i])
          } catch (e) {}
        }
      }
      this.refreshCacheSize()
      appStore.showToast('缓存已清除')
    } catch (e) {
      appStore.showToast('清除缓存失败')
    } finally {
      if (context) {
        context.area = originArea
      }
      if (appContext) {
        appContext.area = originAppArea
      }
      this.clearingCache = false
    }
  }

  private async handleExport(): Promise<void> {
    try {
      const token = appStore.auth.token
      const session = appStore.getSession(token)
      if (!session) {
        appStore.showToast('未找到登录会话')
        return
      }

      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const userName = session.nickName || `User${session.uid}`
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.newFileNames = [`nga_${userName}.txt`]
      documentSaveOptions.fileSuffixChoices = ['文档|.txt']

      const documentViewPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await documentViewPicker.save(documentSaveOptions)

      if (uris.length === 0) {
        return
      }

      const content = `NGA_UID=${session.uid}\nNGA_CID=${session.cid}`
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)
      appStore.showToast('账号凭证已导出')
    } catch (e) {
      appStore.showToast('导出失败')
    }
  }

  private imageStrategyLabel(strategy: string): string {
    if (strategy === ImageLoadStrategy.MANUAL) {
      return '手动加载'
    }
    if (strategy === ImageLoadStrategy.WIFI_ONLY) {
      return 'WiFi下加载'
    }
    return '始终加载'
  }

  private imageStrategyOptions(): ActionOption[] {
    return [
      { label: '始终加载（主动式）', value: 0 },
      { label: '手动加载（被动式）', value: 1 },
      { label: '只在WiFi下加载', value: 2 },
    ]
  }

  private threadNavLabel(mode: string): string {
    if (mode === ThreadNavMode.PAGE) {
      return '传统翻页'
    }
    return '无缝加载'
  }

  private threadNavOptions(): ActionOption[] {
    return [
      { label: '无缝加载（连续滚动）', value: parseInt(ThreadNavMode.SEAMLESS) },
      { label: '传统翻页（跳转器换页）', value: parseInt(ThreadNavMode.PAGE) },
    ]
  }

  private showThreadNavPicker(): void {
    this.threadNavDialogController = new CustomDialogController({
      builder: ActionSheetDialog({
        title: '帖子楼层导航',
        options: this.threadNavOptions(),
        selected: parseInt(appStore.settings.threadNavMode),
        onSelect: (v: number): void => {
          appStore.setThreadNavMode(String(v))
          this.threadNavBadge = this.threadNavLabel(String(v))
        }
      }),
      autoCancel: true,
      customStyle: true
    })
    this.threadNavDialogController?.open()
  }

  private prefetchPageLabel(count: number): string {
    if (count <= 0) {
      return '关闭'
    }
    return `${count} 页`
  }

  private prefetchPageOptions(): ActionOption[] {
    const options: ActionOption[] = []
    for (let i = 0; i <= 5; i++) {
      options.push({
        label: i === 0 ? '关闭（不预加载）' : `${i} 页`,
        value: i
      })
    }
    return options
  }

  private showPrefetchPagePicker(): void {
    this.prefetchPageDialogController = new CustomDialogController({
      builder: ActionSheetDialog({
        title: '预加载页数',
        options: this.prefetchPageOptions(),
        selected: appStore.settings.prefetchPageCount,
        onSelect: (v: number): void => {
          appStore.setPrefetchPageCount(v)
          this.prefetchPageBadge = this.prefetchPageLabel(v)
        }
      }),
      autoCancel: true,
      customStyle: true
    })
    this.prefetchPageDialogController?.open()
  }

  private showImageStrategyPicker(): void {
    this.imageStrategyDialogController = new CustomDialogController({
      builder: ActionSheetDialog({
        title: '图片加载模式',
        options: this.imageStrategyOptions(),
        selected: parseInt(appStore.settings.imageLoadStrategy),
        onSelect: (v: number): void => {
          appStore.setImageLoadStrategy(String(v))
          this.imageStrategyBadge = this.imageStrategyLabel(String(v))
        }
      }),
      autoCancel: true,
      customStyle: true
    })
    this.imageStrategyDialogController?.open()
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
                .width('100%').padding({ bottom: 10 })

              Row() {
                ForEach(THEME_OPTIONS, (theme: ThemeOption) => {
                  this.ThemeCard(theme)
                }, (theme: ThemeOption) => theme.name)
              }
              .width('100%')
            }
            .width('92%')
            .backgroundColor(AppColors.bgTertiary)
            .borderRadius(12)
            .padding(12)
            .margin({ top: 16 })

            // ---- Block 1: 黑名单管理 / 用户备注 / 关键词屏蔽 / 自动签到 ----
            Column() {
              this.SettingRow($r('app.media.icon_block'), IconColors.block, '黑名单管理', '', () => {
                routerStore.navigateActivity(Screen.blacklist())
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              this.SettingRow($r('app.media.icon_person'), IconColors.textFields, '用户备注', '', () => {
                routerStore.navigateActivity(Screen.notes())
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              this.SettingRow($r('app.media.icon_text_fields'), IconColors.textFields, '关键词屏蔽', '', () => {
                routerStore.navigateActivity(Screen.filterKeywords())
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_calendar_check')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.checkin).margin({ right: 12 })

                Text('自动签到').fontSize(17).layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: appStore.settings.autoCheckin })
                  .onChange((v: boolean) => {
                    appStore.setAutoCheckin(v)
                  })
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

            }
            .width('92%')
            .backgroundColor(AppColors.bgTertiary)
            .borderRadius(12)
            .margin({ top: 12 })

            // ---- Block 2: 智感握姿 / 语音朗读 ----
            Column() {
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

              this.SettingRow($r('app.media.icon_volume_up'), '#5AC8FA', '语音朗读', '', () => {
                routerStore.navigateActivity(Screen.ttsSettings())
              })
            }
            .width('92%')
            .backgroundColor(AppColors.bgTertiary)
            .borderRadius(12)
            .margin({ top: 12 })

            // ---- Block 3A: 显示签名 / 图片加载模式 / 预热图片尺寸 ----
            Column() {
              Row() {
                Stack() {
                  Image($r('app.media.icon_clipboard')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.signature).margin({ right: 12 })

                Text('显示签名').fontSize(17).layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: appStore.settings.showSignature })
                  .onChange((v: boolean) => {
                    appStore.setShowSignature(v)
                  })
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_image')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.globe).margin({ right: 12 })

                Text('图片加载模式').fontSize(17).layoutWeight(1)

                Text(this.imageStrategyBadge).fontSize(15).fontColor(AppColors.textSecondary).margin({ right: 8 })

                Text('>').fontSize(16).fontColor(AppColors.chevron)
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.showImageStrategyPicker()
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_image')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.moon).margin({ right: 12 })

                Column() {
                  Text('预热图片尺寸').fontSize(17).width('100%')
                  Text('关闭后不再提前获取图片尺寸信息').fontSize(12).fontColor(AppColors.textSecondary).width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: appStore.settings.enableImageSizePrefetch })
                  .onChange((v: boolean) => {
                    appStore.setEnableImageSizePrefetch(v)
                  })
              }
              .width('100%').height(52).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_settings')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.settings).margin({ right: 12 })

                Text('帖子楼层导航').fontSize(17).layoutWeight(1)

                Text(this.threadNavBadge).fontSize(15).fontColor(AppColors.textSecondary).margin({ right: 8 })

                Text('>').fontSize(16).fontColor(AppColors.chevron)
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.showThreadNavPicker()
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_image')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.globe).margin({ right: 12 })

                Text('预加载页数').fontSize(17).layoutWeight(1)

                Text(this.prefetchPageBadge).fontSize(15).fontColor(AppColors.textSecondary).margin({ right: 8 })

                Text('>').fontSize(16).fontColor(AppColors.chevron)
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.showPrefetchPagePicker()
              })
            }
            .width('92%')
            .backgroundColor(AppColors.bgTertiary)
            .borderRadius(12)
            .margin({ top: 12 })

            // ---- Block 3B: 导出账号凭证 / 清除缓存 / 退出登录 ----
            Column() {
              this.SettingRow($r('app.media.icon_export'), IconColors.checkin, '导出账号凭证', '', () => {
                this.handleExport()
              })

              Divider().margin({ left: 60 }).color(AppColors.separator)

              Row() {
                Stack() {
                  Image($r('app.media.icon_delete')).width(17).height(17).fillColor(AppColors.white)
                }
                .width(29).height(29).borderRadius(6).backgroundColor(IconColors.hand).margin({ right: 12 })

                Text('清除缓存').fontSize(17).layoutWeight(1)

                Text(this.cacheSizeText).fontSize(15).fontColor(AppColors.textSecondary).margin({ right: 8 })

                Text('>').fontSize(16).fontColor(AppColors.chevron)
              }
              .width('100%').height(44).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.clearCacheDialogController?.open()
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
      Stack() {
        if (theme.name === 'system') {
          Column() {
            Stack() {
              Column() {
                Row().width('80%').height(3).backgroundColor('#C08A4A').borderRadius(2)
                Row().width('60%').height(3).backgroundColor('#3E2A1D').borderRadius(2).opacity(0.5).margin({ top: 5 })
                Row().width('45%').height(3).backgroundColor('#3E2A1D').borderRadius(2).opacity(0.25).margin({ top: 4 })
              }
              .padding(8).alignItems(HorizontalAlign.Start).width('100%')
            }
            .width('100%').layoutWeight(1).backgroundColor('#FEFAF6')

            Stack() {
              Column() {
                Row().width('80%').height(3).backgroundColor('#D4A85A').borderRadius(2)
                Row().width('60%').height(3).backgroundColor('#EAE2D8').borderRadius(2).opacity(0.5).margin({ top: 5 })
                Row().width('45%').height(3).backgroundColor('#EAE2D8').borderRadius(2).opacity(0.25).margin({ top: 4 })
              }
              .padding(8).alignItems(HorizontalAlign.Start).width('100%')
            }
            .width('100%').layoutWeight(1).backgroundColor('#1A1A1E')
          }
          .width('100%').height('100%')
        } else {
          Column() {
            Row().width('100%').height(2).backgroundColor(theme.primaryColor)
            Column() {
              Row().width('55%').height(3).backgroundColor(theme.textColor).borderRadius(2).opacity(0.55)
              Row().width('35%').height(3).backgroundColor(theme.textColor).borderRadius(2).opacity(0.25).margin({ top: 5 })
              Row().width('70%').height(3).backgroundColor(theme.textColor).borderRadius(2).opacity(0.35).margin({ top: 5 })
              Row().width('45%').height(3).backgroundColor(theme.textColor).borderRadius(2).opacity(0.15).margin({ top: 5 })
            }
            .padding(8).alignItems(HorizontalAlign.Start).width('100%')
          }
          .width('100%').height('100%').backgroundColor(theme.bgColor)
        }
      }
      .width('100%').height(90).borderRadius(8)
      .clip(true)
      .border({
        width: this.themeName === theme.name ? 2 : 1,
        color: this.themeName === theme.name ? AppColors.primary : AppColors.separator
      })

      Row() {
        Text(theme.label).fontSize(13).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Medium)
        Blank()
        if (this.themeName === theme.name) {
          Image($r('app.media.icon_check')).width(14).height(14).fillColor(AppColors.primary)
        } else {
          Stack().width(14).height(14).borderRadius(7).border({ width: 1.5, color: AppColors.separator })
        }
      }
      .width('100%').margin({ top: 8 })
    }
    .layoutWeight(1)
    .margin({ left: 4, right: 4 })
    .padding(8)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(10)
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
