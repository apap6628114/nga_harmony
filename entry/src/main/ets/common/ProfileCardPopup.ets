import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { ProfileData, AdminForumsData } from '../model/User'
import { AppColors } from '../common/Constants'
import { formatTime, fmtNum, escHtml } from '../common/Utils'
import { Avatar } from '../common/Avatar'

@Component
export struct ProfileCardPopup {
  @Prop targetUid: string = ''
  @Prop currentBreakpoint: string = 'sm'
  @State profile: ProfileData | null = null
  @State isLoading: boolean = true
  @State hasError: boolean = false
  @StorageProp('profileVersion') @Watch('onProfileVersionChange') profileVersion: number = 0
  onClose: () => void = () => {}

  aboutToAppear(): void {
    const cached = appStore.getCachedProfile(this.targetUid)
    if (cached) {
      this.profile = cached
      this.isLoading = false
    }
    appStore.ensureProfile(this.targetUid)
  }

  private onProfileVersionChange(): void {
    const cached = appStore.getCachedProfile(this.targetUid)
    if (cached) {
      this.profile = cached
      this.isLoading = false
      this.hasError = false
    }
  }

  private navigateProfile(uid: string): void {
    this.onClose()
    routerStore.navigateActivity(Screen.profile(uid))
  }

  private navigateAuthorPosts(uid: string, name: string, searchpost: boolean): void {
    this.onClose()
    routerStore.navigateActivity(Screen.topicList(
      name + (searchpost ? '的回帖' : '的主题'), -1, uid, '', searchpost ? '1' : ''
    ))
  }

  private joinForumNames(forums: AdminForumsData[]): string {
    const names: string[] = []
    for (let i = 0; i < forums.length; i++) {
      names.push(forums[i].forumName)
    }
    return names.join(', ')
  }

  private joinTitleHonor(title: string, honor: string): string {
    const parts: string[] = []
    if (title && title.length > 0) parts.push(title)
    if (honor && honor.length > 0) parts.push(honor)
    return parts.join(' · ')
  }

  build() {
    Column() {
      if (this.isLoading) {
        this.LoadingContent()
      } else if (this.hasError) {
        this.ErrorContent()
      } else if (this.profile) {
        this.ProfileContent(this.profile!)
      }
    }
    .width(280)
    .backgroundColor(AppColors.bg)
    .borderRadius(14)
    .shadow({ radius: 16, color: '#30000000', offsetY: 4 })
    .clip(true)
  }

  @Builder
  LoadingContent() {
    Column() {
      LoadingProgress().width(20).height(20).color(AppColors.textTertiary)
      Text('加载中...').fontSize(14).fontColor(AppColors.textTertiary).margin({ top: 8 })
    }
    .width('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ErrorContent() {
    Column() {
      Text('获取用户信息失败').fontSize(14).fontColor(AppColors.textTertiary)
    }
    .width('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ProfileContent(profile: ProfileData) {
    Column() {
      Row() {
        Avatar({ avatar: profile.avatarUrl, uid: profile.uid, name: profile.userName, avatarSize: 50 })

        Column() {
          Row() {
            Text(escHtml(profile.userName))
              .fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColors.textPrimary)
            if (profile.group && profile.group.length > 0) {
              Text(escHtml(profile.group))
                .fontSize(10).fontColor(AppColors.textSecondary)
                .backgroundColor(AppColors.bgSecondary).borderRadius(4)
                .padding({ left: 5, right: 5, top: 2, bottom: 2 }).margin({ left: 6 })
            }
            if (profile.muteTime && profile.muteTime.length > 0) {
              Text('禁言中')
                .fontSize(10).fontColor(Color.White)
                .backgroundColor(AppColors.destructive).borderRadius(4)
                .padding({ left: 5, right: 5, top: 2, bottom: 2 }).margin({ left: 4 })
            }
          }
          .alignItems(VerticalAlign.Center)

          if (profile.title || profile.honor) {
            Text(escHtml(this.joinTitleHonor(profile.title, profile.honor)))
              .fontSize(12).fontColor(AppColors.textSecondary).margin({ top: 3 })
          }

          Text(`UID: ${escHtml(profile.uid)}`)
            .fontSize(11).fontColor(AppColors.textTertiary).margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })
      .alignItems(VerticalAlign.Center)

      if (Number(profile.posts) || Number(profile.fame) || Number(profile.rvrc) || Number(profile.money)) {
        Row() {
          if (Number(profile.posts)) {
            this.StatItem(fmtNum(profile.posts), '发帖')
          }
          if (Number(profile.fame)) {
            this.StatItem(fmtNum(profile.fame), '威望')
          }
          if (Number(profile.rvrc)) {
            this.StatItem(fmtNum(profile.rvrc), 'RVRC')
          }
          if (Number(profile.money)) {
            this.StatItem(fmtNum(profile.money), '金钱')
          }
        }
        .width('100%')
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(8)
        .padding(6)
        .margin({ top: 12 })
      }

      Column() {
        this.DetailRows(profile)

        if (profile.sign && profile.sign.length > 0) {
          Text(escHtml(profile.sign))
            .fontSize(12).fontColor(AppColors.textTertiary)
            .margin({ top: 8 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .padding({ left: 16, right: 16 })
      .width('100%')

      Row() {
        Text('主题').fontSize(12).fontColor(AppColors.primary).layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.navigateAuthorPosts(profile.uid, profile.userName, false))
        Divider().vertical(true).height(16).alignSelf(ItemAlign.Center).color(AppColors.separator)
        Text('回帖').fontSize(12).fontColor(AppColors.primary).layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.navigateAuthorPosts(profile.uid, profile.userName, true))
        Divider().vertical(true).height(16).alignSelf(ItemAlign.Center).color(AppColors.separator)
        Text('资料').fontSize(12).fontColor(AppColors.primary).layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.navigateProfile(profile.uid))
      }
      .width('100%')
      .border({ width: { top: 0.5 }, color: AppColors.separator })
      .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 0 })
  }

  @Builder
  StatItem(value: string, label: string) {
    Column() {
      Text(value).fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppColors.textPrimary)
      Text(label).fontSize(10).fontColor(AppColors.textTertiary).margin({ top: 1 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  DetailRows(profile: ProfileData) {
    Column() {
      if (profile.regdate) {
        this.DetailRow('注册日期', formatTime(Number(profile.regdate)))
      }
      if (profile.ipLoc) {
        this.DetailRow('IP属地', profile.ipLoc)
      }
      if (profile.followByNum && Number(profile.followByNum) > 0) {
        this.DetailRow('被关注', profile.followByNum)
      }
      if (profile.adminForums && profile.adminForums.length > 0) {
        this.DetailRow('管理版面', this.joinForumNames(profile.adminForums))
      }
    }
    .width('100%')
    .margin({ top: 4 })
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontColor(AppColors.textSecondary)
      Text(escHtml(value)).fontSize(12).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Medium)
        .layoutWeight(1).textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }
}
