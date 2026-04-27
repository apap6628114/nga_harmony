import { appStore } from '../store/AppStore'
import { routerStore, Screen } from '../store/RouterStore'
import { AppColors } from '../common/Constants'
import { Avatar } from '../common/Avatar'
import { CommunityTabContent } from './CommunityTabContent'

@Component
export struct SidebarComponent {
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  build() {
    Column() {
      Column() {
        Avatar({
          avatar: appStore.auth.avatarUrl,
          uid: appStore.auth.uid,
          name: appStore.auth.nickName,
          avatarSize: 36
        })
        Text(appStore.auth.nickName || '未登录')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
      }
      .width('100%')
      .padding({ top: 14 + this.statusBarHeight, bottom: 14 })
      .alignItems(HorizontalAlign.Center)
      .border({ width: { bottom: 0.5 }, color: AppColors.separator })
      .onClick(() => {
        if (appStore.auth.uid) {
          routerStore.navigateActivity(Screen.profile(appStore.auth.uid))
        }
      })

      Row() {
        Image($r('app.media.icon_search'))
          .width(14).height(14).margin({ right: 6 })
        Text('搜索板块、主题...')
          .fontSize(12).fontColor(AppColors.textTertiary)
      }
      .width('100%').height(36).padding({ left: 10, right: 10 })
      .backgroundColor(AppColors.bgSecondary).borderRadius(8)
      .margin({ left: 8, right: 8, top: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        routerStore.navigateSearch()
      })

      Column() {
        CommunityTabContent({ currentBreakpoint: this.currentBreakpoint })
      }
      .layoutWeight(1)
    }
    .width(180)
    .height('100%')
    .backgroundColor(AppColors.bgTertiary)
    .border({ width: { right: 0.5 }, color: AppColors.separator })
  }
}
