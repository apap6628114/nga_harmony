/**
 * 主页面 - 统一三列 Panel 架构
 *
 * 使用单一布局结构而非三个独立 @Builder, 所有面板保持在相同树节点位置,
 * 通过 .visibility() 控制显隐, 避免断点切换时组件重建导致 @State 丢失.
 *
 * 第一列: 侧边栏, 固定且唯一, sm 下隐藏
 * 第二列: 论坛板块 (或 fallback), sm/md 下单列模式 (activity 优先)
 * 第三列: 活动列, 仅在对应数据存在时渲染
 *
 * sm (一列): 侧边栏隐藏, 单列内容 (activity > board > 社区网格)
 * md (两列): 侧边栏 + 单列内容 (activity > board > empty)
 * lg (三列): 侧边栏 + 板块列 + 活动列 (并行显示)
 */

import { appStore } from '../store/AppStore'
import { routerStore, RouterStoreClass } from '../store/RouterStore'
import router from '@ohos.router'
import { floatingLayerStore, FloatingLayerStoreClass, FloatingPage } from '../store/FloatingLayerStore'
import { ActivityPanelComponent } from './ActivityPanelComponent'
import { BoardPanelComponent } from './BoardPanelComponent'
import { SidebarComponent } from './SidebarComponent'
import { CommunityTabContent } from './CommunityTabContent'
import { FloatingLayerComponent } from './FloatingLayerComponent'
import { EmptyHint } from '../common/EmptyHint'
import { ToastComponent } from '../common/Toast'

@Entry
@Component
struct MainPage {
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'sm'
  @StorageProp('profileVersion') @Watch('onProfileRefresh') profileVersion: number = 0
  @State private router: RouterStoreClass = routerStore
  @State private floating: FloatingLayerStoreClass = floatingLayerStore

  aboutToAppear(): void {
    this.checkAuth()
  }

  private onProfileRefresh(): void {
    const cached = appStore.getCachedProfile(appStore.auth.uid)
    if (cached) {
      appStore.auth.nickName = cached.userName
      appStore.auth.avatarUrl = cached.avatarUrl
    }
  }

  onBackPress(): boolean {
    if (this.floating.size > 0) {
      if (this.floating.top === FloatingPage.REPLY_DIALOG) {
        this.floating.notifyReplyCloseRequested()
      } else if (this.floating.top === FloatingPage.CONFIRM_DIALOG) {
        this.floating.hideConfirm()
      } else {
        this.floating.pop()
      }
      return true
    }
    if (this.router.activityStack.length > 0) {
      this.router.back()
      return true
    }
    if (this.router.boardSlot) {
      if (this.currentBreakpoint === 'sm' || this.router.boardSlot.type === 'search') {
        this.router.back()
        return true
      }
      return true
    }
    return false
  }

  build() {
    Stack() {
      Row() {
        SidebarComponent()
          .width(180)
          .height('100%')
          .visibility(this.currentBreakpoint === 'sm' ? Visibility.None : Visibility.Visible)

        Row() {
          Column() {
            if (this.currentBreakpoint === 'sm') {
              CommunityTabContent({ currentBreakpoint: 'sm' })
                .width('100%').height('100%')
                .visibility(!this.router.boardSlot && !this.router.topActivity
                  ? Visibility.Visible : Visibility.None)
            }
            if (this.router.boardSlot) {
              BoardPanelComponent({ boardSlot: this.router.boardSlot })
            }
            if (this.currentBreakpoint !== 'sm' && !this.router.boardSlot && !this.router.topActivity) {
              EmptyHint()
            }
          }
          .height('100%')
          .width(this.getBoardColWidth())
          .visibility(this.getBoardColVisibility())

          Column() {
            if (this.router.topActivity) {
              ActivityPanelComponent({ topActivity: this.router.topActivity })
            }
          }
          .layoutWeight(1)
          .height('100%')
          .visibility(this.getActivityColVisibility())
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')

      FloatingLayerComponent({ currentBreakpoint: this.currentBreakpoint })
      ToastComponent()
    }
    .width('100%').height('100%')
  }

  private getBoardColVisibility(): Visibility {
    if (this.currentBreakpoint === 'lg') {
      return (this.router.boardSlot || !this.router.topActivity) ? Visibility.Visible : Visibility.None
    }
    return this.router.topActivity ? Visibility.None : Visibility.Visible
  }

  private getBoardColWidth(): string {
    if (this.currentBreakpoint === 'lg' && this.router.topActivity && this.router.boardSlot) {
      return '40%'
    }
    return '100%'
  }

  private getActivityColVisibility(): Visibility {
    return this.router.topActivity ? Visibility.Visible : Visibility.None
  }

  private async checkAuth(): Promise<void> {
    if (!appStore.auth.isAuthenticated) {
      router.replaceUrl({ url: 'pages/LoginPage' })
      return
    }

    const cached = appStore.getCachedProfile(appStore.auth.uid)
    if (cached) {
      appStore.auth.nickName = cached.userName
      appStore.auth.avatarUrl = cached.avatarUrl
    }

    appStore.ensureProfile(appStore.auth.uid)
    appStore.ensureFavorites()
  }
}
