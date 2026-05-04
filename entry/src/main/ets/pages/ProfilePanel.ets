import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { getNotifications, checkin } from '../service/NgaApi'
import { ProfileData, ReputationData } from '../model/User'
import { AppColors, IconColors, BreakpointType } from '../common/Constants'
import { formatTime, fmtNum, escHtml, unescapeHtml } from '../common/Utils'
import { Avatar } from '../common/Avatar'
import { AnonymousName } from '../common/AnonymousName'
import { MakeNoteDialog } from '../common/Dialogs'
import { PanelNavBar } from '../common/PanelNavBar'

@Component
export struct ProfilePanel {
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @State errorMsg: string = ''
  @State profile: ProfileData | null = null
  @State unreadNotifications: number = 0
  @State unreadMessages: number = 0
  @State checkinLoading: boolean = false
  @State checkinResult: string = ''
  noteDialogController?: CustomDialogController

  private showNoteDialog(): void {
    this.noteDialogController = new CustomDialogController({
      builder: MakeNoteDialog({
        userName: this.profile?.userName ?? '',
        uid: this.uid,
        currentNote: appStore.getNote(this.uid),
        onConfirm: (note: string, uid: string, userName: string): void => {
          appStore.addOrUpdateNote(uid, userName, note)
          appStore.showToast('备注已保存')
        }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    })
    this.noteDialogController.open()
  }
  @StorageProp('profileVersion') @Watch('onProfileVersionChange') profileVersion: number = 0
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  @Prop @Watch('onUidChange') uid: string = ''
  private isOwnProfile: boolean = false
  private uidInitialized: boolean = false

  aboutToAppear(): void {
    this.uidInitialized = true
    this.isOwnProfile = appStore.auth.uid === this.uid
    const cached = appStore.getCachedProfile(this.uid)
    if (cached) {
      this.profile = cached
      this.isLoading = false
    }
    appStore.ensureProfile(this.uid)
    if (this.isOwnProfile) {
      this.loadUnreadCount()
    }
  }

  private onUidChange(): void {
    if (!this.uidInitialized) {
      return
    }
    this.profile = null
    this.isLoading = true
    this.hasError = false
    this.isOwnProfile = appStore.auth.uid === this.uid
    const cached = appStore.getCachedProfile(this.uid)
    if (cached) {
      this.profile = cached
      this.isLoading = false
    }
    appStore.ensureProfile(this.uid)
    if (this.isOwnProfile) {
      this.loadUnreadCount()
    }
  }

  private onProfileVersionChange(): void {
    const cached = appStore.getCachedProfile(this.uid)
    if (cached) {
      this.profile = cached
      this.isLoading = false
      this.hasError = false
    }
  }

  private async loadUnreadCount(): Promise<void> {
    try {
      const result = await getNotifications(appStore.auth.token)
      if (result.ok && result.data) {
        const notifications = result.data as import('../model/Notification').NotificationInfo[]
        let unreadCount: number = 0
        for (let i: number = 0; i < notifications.length; i++) {
          if ((notifications[i] as import('../model/Notification').NotificationInfo).unread) {
            unreadCount++
          }
        }
        this.unreadNotifications = unreadCount
        AppStorage.setOrCreate('unreadNotiCount', this.unreadNotifications)
      }
    } catch (e) {
    }
  }

  private async handleCheckin(): Promise<void> {
    this.checkinLoading = true
    try {
      const result = await checkin(appStore.auth.token)
      if (result.ok) {
        this.checkinResult = '签到成功'
      } else {
        this.checkinResult = result.error || '签到失败'
      }
    } catch (e) {
      this.checkinResult = '签到失败'
    }
    this.checkinLoading = false
    appStore.showToast(this.checkinResult)
    setTimeout(() => { this.checkinResult = '' }, 3000)
  }

  private formatBadge(count: number): string {
    if (count <= 0) return ''
    if (count > 99) return '99+'
    return String(count)
  }

  private getStatGridTemplate(): string {
    const cols: number = new BreakpointType(2, 3, 4).getValue(this.currentBreakpoint)
    let template: string = ''
    for (let i: number = 0; i < cols; i++) {
      template += '1fr '
    }
    return template.trim()
  }

  private dispatchAction(actionType: number): void {
    switch (actionType) {
      case 0:
        routerStore.navigateActivity(Screen.messages())
        break
      case 1:
        routerStore.navigateActivity(Screen.notifications())
        break
      case 2:
        routerStore.navigateActivity(Screen.topicList('我的收藏', 0, '', '1'))
        break
      case 3:
        routerStore.navigateActivity(Screen.browseHistory())
        break
      case 4:
        this.handleCheckin()
        break
      case 5:
        routerStore.navigateActivity(Screen.settings())
        break
      default:
        break
    }
  }

  @Builder
  ActionRow(iconRes: Resource, iconColor: string, label: string, badge: string, actionType: number) {
    Row() {
      Stack() {
      Image(iconRes)
        .width(17).height(17)
        .fillColor(AppColors.white)
      }
      .width(29)
      .height(29)
      .borderRadius(6)
      .backgroundColor(iconColor)
      .margin({ right: 12 })

      Text(label)
        .fontSize(17)
        .layoutWeight(1)

      if (badge) {
        Text(badge)
          .fontSize(12)
          .fontColor(AppColors.white)
          .backgroundColor(AppColors.destructive)
          .borderRadius(10)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .fontWeight(FontWeight.Bold)
          .margin({ right: 8 })
      }

      Text('>')
        .fontSize(16)
        .fontColor(AppColors.chevron)
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.dispatchAction(actionType))
  }

  build() {
    Stack() {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(28).height(28).color(AppColors.textTertiary)
            Text('加载中...')
              .fontSize(14)
              .fontColor(AppColors.textTertiary)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 44 + this.statusBarHeight })
        } else if (this.hasError) {
          Column() {
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor(AppColors.textTertiary)
              .margin({ bottom: 12 })
            Button('重试')
              .fontSize(14)
              .fontColor(AppColors.primary)
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius(10)
              .onClick(() => { this.isLoading = true; this.hasError = false; appStore.ensureProfile(this.uid) })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 44 + this.statusBarHeight })
        } else if (this.profile) {
          Scroll() {
            Column() {
              Row().width('100%').height(44 + this.statusBarHeight)

              Column() {
                Column() {
                Avatar({ avatar: this.profile!.avatarUrl, uid: String(this.profile!.uid), name: this.profile!.userName, avatarSize: 80 })

              Text(unescapeHtml(this.profile!.userName))
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .margin({ top: 12 })

              Row() {
                if (this.profile!.group) {
                  Text(unescapeHtml(this.profile!.group))
                    .fontSize(12)
                    .fontColor(AppColors.primary)
                    .backgroundColor(AppColors.primaryLight)
                    .borderRadius(4)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                }
                Text(`UID: ${escHtml(this.profile!.uid)}`)
                  .fontSize(13)
                  .fontColor(AppColors.textSecondary)
                  .margin({ left: 8 })

                if (this.profile!.ipLoc) {
                  Row() {
                    Image($r('app.media.icon_location')).width(13).height(13).fillColor(AppColors.textSecondary).margin({ right: 3 })
                    Text(unescapeHtml(this.profile!.ipLoc)).fontSize(13).fontColor(AppColors.textSecondary)
                  }.margin({ left: 8 })
                }
              }
              .margin({ top: 8 })

              if (this.profile!.title) {
                Text(unescapeHtml(this.profile!.title))
                  .fontSize(13)
                  .fontColor(AppColors.textTertiary)
                  .margin({ top: 6 })
              }
              if (this.profile!.honor) {
                Text(unescapeHtml(this.profile!.honor))
                  .fontSize(12)
                  .fontColor(AppColors.warning)
                  .fontWeight(FontWeight.Medium)
                  .margin({ top: 4 })
              }

              if (appStore.getNote(this.uid).length > 0) {
                Text('备注: ' + appStore.getNote(this.uid))
                  .fontSize(13)
                  .fontColor(AppColors.warning)
                  .margin({ top: 6 })
              }
            }
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 24 })

            Grid() {
              GridItem() {
                Column() {
                  Row() {
                    Image($r('app.media.icon_chat_bubble')).width(16).height(16).fillColor(AppColors.textSecondary)
                    Text('发帖数').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(fmtNum(this.profile!.posts)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
              GridItem() {
                Column() {
                  Row() {
                    Image($r('app.media.icon_money')).width(16).height(16).fillColor(AppColors.textSecondary)
                    Text('金钱').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(fmtNum(this.profile!.money)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
              GridItem() {
                Column() {
                  Row() {
                    Image($r('app.media.icon_medal')).width(16).height(16).fillColor(AppColors.textSecondary)
                    Text('威望').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(fmtNum(this.profile!.rvrc)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
              GridItem() {
                Column() {
                  Row() {
                    Image($r('app.media.icon_calendar')).width(16).height(16).fillColor(AppColors.textSecondary)
                    Text('注册日期').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(this.profile!.regdate ? formatTime(Number(this.profile!.regdate)) : '未知').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
              GridItem() {
                Column() {
                  Row() {
                    Image($r('app.media.icon_people')).width(16).height(16).fillColor(AppColors.textSecondary)
                    Text('会员组').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(this.profile!.group || '普通会员').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
              if (Number(this.profile!.fame) > 0) {
                GridItem() {
                  Column() {
                    Row() {
                      Image($r('app.media.icon_star')).width(16).height(16).fillColor(AppColors.textSecondary)
                      Text('声望').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                    }
                    .alignItems(VerticalAlign.Center)
                    Text(fmtNum(this.profile!.fame)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                  }
                  .alignItems(HorizontalAlign.Center)
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                }
              }
              if (Number(this.profile!.followByNum) > 0) {
                GridItem() {
                  Column() {
                    Row() {
                      Image($r('app.media.icon_shield')).width(16).height(16).fillColor(AppColors.textSecondary)
                      Text('被关注').fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 })
                    }
                    .alignItems(VerticalAlign.Center)
                    Text(this.profile!.followByNum).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary).margin({ top: 6 })
                  }
                  .alignItems(HorizontalAlign.Center)
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                }
              }
            }
            .columnsTemplate(this.getStatGridTemplate())
            .columnsGap(8)
            .rowsGap(8)
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
            }
            .width('92%')
            .backgroundColor(AppColors.bgTertiary)
            .borderRadius(12)
            .margin({ top: 12 })

            if (this.profile!.medal) {
              Column() {
                Text('勋章')
                  .fontSize(13)
                  .fontColor(AppColors.textSecondary)
                  .margin({ bottom: 4 })
                RichText(this.profile!.medal)
                  .width('100%')
              }
              .width('92%')
              .padding(16)
              .backgroundColor(AppColors.bgTertiary)
              .borderRadius(12)
              .margin({ top: 12 })
              .alignItems(HorizontalAlign.Start)
            }

            if (this.profile!.sign) {
              Column() {
                Text('签名')
                  .fontSize(13)
                  .fontColor(AppColors.textSecondary)
                  .margin({ bottom: 4 })
                RichText(this.profile!.sign)
                  .width('100%')
              }
              .width('92%')
              .padding(16)
              .backgroundColor(AppColors.bgTertiary)
              .borderRadius(12)
              .margin({ top: 12 })
              .alignItems(HorizontalAlign.Start)
            }

            if (this.profile!.reputationEntryList && this.profile!.reputationEntryList.length > 0) {
              Column() {
                Text('威望记录')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textSecondary)
                  .padding({ top: 12, bottom: 4, left: 16, right: 16 })

                ForEach(this.profile!.reputationEntryList, (entry: ReputationData, index: number) => {
                  Column() {
                    Row() {
                      Text(entry.reputation > 0 ? `+${entry.reputation}` : `${entry.reputation}`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(entry.reputation > 0 ? AppColors.success : entry.reputation < 0 ? AppColors.destructive : AppColors.textTertiary)
                      Text(entry.time ? formatTime(entry.time) : '')
                        .fontSize(12)
                        .fontColor(AppColors.textTertiary)
                        .layoutWeight(1)
                        .textAlign(TextAlign.End)
                    }
                    .width('100%')
                    if (entry.topicSubject) {
                      Text(unescapeHtml(entry.topicSubject))
                        .fontSize(13)
                        .fontColor(AppColors.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                        .width('100%')
                    }
                    if (entry.postContent) {
                      Text(unescapeHtml(entry.postContent))
                        .fontSize(12)
                        .fontColor(AppColors.textTertiary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                        .width('100%')
                    }
                    Row() {
                      Text('来自: ').fontSize(12).fontColor(AppColors.textTertiary)
                      AnonymousName({
                        author: entry.author ?? '',
                        isAnonymous: (entry.author ?? '').startsWith('#anony_') &&
                          (entry.author ?? '').length === 39,
                        fontSize: 12
                      })
                    }
                      .margin({ top: 2 })
                      .width('100%')
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .border({ width: { top: index === 0 ? 0 : 0.5 }, color: AppColors.separator })
                  .alignItems(HorizontalAlign.Start)
                }, (entry: ReputationData, index: number) => `${index}`)
              }
              .width('92%')
              .backgroundColor(AppColors.bgTertiary)
              .borderRadius(12)
              .margin({ top: 12 })
              .alignItems(HorizontalAlign.Start)
              .clip(true)
            }

            if (this.isOwnProfile) {
              Column() {
                this.ActionRow($r('app.media.icon_mail'), IconColors.mail, '私信', this.formatBadge(this.unreadMessages), 0)
                Divider().margin({ left: 60 }).color(AppColors.separator)
                this.ActionRow($r('app.media.icon_bell'), IconColors.bell, '通知', this.formatBadge(this.unreadNotifications), 1)
                Divider().margin({ left: 60 }).color(AppColors.separator)
                this.ActionRow($r('app.media.icon_star'), IconColors.star, '收藏主题', '', 2)
                Divider().margin({ left: 60 }).color(AppColors.separator)
                this.ActionRow($r('app.media.icon_clock'), IconColors.clock, '浏览历史', '', 3)
                Divider().margin({ left: 60 }).color(AppColors.separator)

                // 签到行 - 内联，不使用 @Builder
                Row() {
                  Stack() {
                    Image($r('app.media.icon_check'))
                      .width(17).height(17)
                      .fillColor(AppColors.white)
                  }
                  .width(29)
                  .height(29)
                  .borderRadius(6)
                  .backgroundColor(IconColors.checkin)
                  .margin({ right: 12 })

                  Text(this.checkinLoading ? '签到中...' : this.checkinResult || '每日签到')
                    .fontSize(17)
                    .layoutWeight(1)

                  Text('>')
                    .fontSize(16)
                    .fontColor(AppColors.chevron)
                }
                .width('100%')
                .height(44)
                .padding({ left: 16, right: 16 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.checkinLoading = true
                  checkin(appStore.auth.token).then((result) => {
                    if (result.ok) {
                      this.checkinResult = '签到成功'
                    } else {
                      this.checkinResult = result.error || '签到失败'
                    }
                    this.checkinLoading = false
                    appStore.showToast(this.checkinResult)
                    setTimeout(() => { this.checkinResult = '' }, 3000)
                  }).catch(() => {
                    this.checkinResult = '签到失败'
                    this.checkinLoading = false
                    appStore.showToast(this.checkinResult)
                  })
                })

                Row() {
                  Stack() {
                    Image($r('app.media.icon_check'))
                      .width(17).height(17)
                      .fillColor(AppColors.white)
                  }
                  .width(29)
                  .height(29)
                  .borderRadius(6)
                  .backgroundColor(IconColors.checkin)
                  .margin({ right: 12 })
                  .opacity(0.5)

                  Text('自动签到')
                    .fontSize(17)
                    .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: appStore.settings.autoCheckin })
                    .onChange((v: boolean) => {
                      appStore.setAutoCheckin(v)
                    })
                }
                .width('100%')
                .height(44)
                .padding({ left: 16, right: 16 })
                .alignItems(VerticalAlign.Center)

                Divider().margin({ left: 60 }).color(AppColors.separator)
                this.ActionRow($r('app.media.icon_settings'), IconColors.settings, '设置', '', 5)
              }
              .width('92%')
              .backgroundColor(AppColors.bgTertiary)
              .borderRadius(12)
              .margin({ top: 12 })
            } else {
              Row() {
                Button('发私信')
                  .fontSize(15)
                  .fontColor(AppColors.white)
                  .backgroundColor(AppColors.primary)
                  .borderRadius(12)
                  .layoutWeight(1)
                  .height(44)
                  .onClick(() => {
                    routerStore.navigateActivity(Screen.messages(this.profile!.userName))
                  })

                Button('备注')
                  .fontSize(15)
                  .fontColor(AppColors.warning)
                  .backgroundColor(AppColors.bgTertiary)
                  .borderRadius(12)
                  .height(44)
                  .margin({ left: 12 })
                  .onClick(() => { this.showNoteDialog() })
              }
              .width('92%')
              .margin({ top: 12 })

              Row() {
                Button('主题')
                  .fontSize(15)
                  .fontColor(AppColors.textPrimary)
                  .backgroundColor(AppColors.bgTertiary)
                  .borderRadius(12)
                  .layoutWeight(1)
                  .height(44)
                  .onClick(() => {
                    routerStore.navigateActivity(Screen.topicList(this.profile!.userName + '的主题', -1, this.profile!.uid))
                  })

                Button('回帖')
                  .fontSize(15)
                  .fontColor(AppColors.textPrimary)
                  .backgroundColor(AppColors.bgTertiary)
                  .borderRadius(12)
                  .layoutWeight(1)
                  .height(44)
                  .margin({ left: 12 })
                  .onClick(() => {
                    routerStore.navigateActivity(Screen.topicList(this.profile!.userName + '的回帖', -1, this.profile!.uid, '', '1'))
                  })

                Button(appStore.settings.blacklist.some(e => e.userId === this.profile!.uid) ? '取消屏蔽' : '加黑')
                  .fontSize(15)
                  .fontColor(AppColors.destructive)
                  .backgroundColor(AppColors.bgTertiary)
                  .borderRadius(12)
                  .height(44)
                  .margin({ left: 12 })
                  .onClick(() => {
                    if (appStore.settings.blacklist.some(e => e.userId === this.profile!.uid)) {
                      appStore.removeBlacklist(this.profile!.uid)
                      appStore.showToast('已取消屏蔽')
                    } else {
                      appStore.addBlacklist({
                        userId: this.profile!.uid,
                        nickName: this.profile!.userName || `User${this.profile!.uid}`
                      })
                      appStore.showToast('已加入黑名单')
                    }
                  })
              }
              .width('92%')
              .margin({ top: 12, bottom: 30 })
            }
          }
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 32 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bg)

    PanelNavBar({ title: '个人主页' })
      .width('100%').position({ x: 0, y: 0 })
  }
  .width('100%')
  .height('100%')
}
}
