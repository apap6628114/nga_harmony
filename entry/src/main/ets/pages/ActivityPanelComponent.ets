import { type NavEntry } from '../store/RouterStore'
import { AppColors } from '../common/Constants'
import { PanelNavBar } from '../common/PanelNavBar'
import { ThreadPanel } from './ThreadPanel'
import { ProfilePanel } from './ProfilePanel'
import { NotificationPanel } from './NotificationPanel'
import { MessageListPanel } from './MessageListPanel'
import { MessageDetailPanel } from './MessageDetailPanel'
import { BlacklistPanel } from './BlacklistPanel'
import { SettingsPanel } from './SettingsPanel'
import { BrowseHistoryPanel } from './BrowseHistoryPanel'
import { TopicListPanel } from './TopicListPanel'

@Component
export struct ActivityPanelComponent {
  @Prop topActivity: NavEntry | null
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  build() {
    Column() {
      if (this.topActivity) {
        if (this.topActivity.screen.type === 'thread') {
          ThreadPanel({
            threadTid: this.topActivity.screen.tid,
            threadPid: this.topActivity.screen.pid,
            navEntryId: this.topActivity.id
          })
        } else if (this.topActivity.screen.type === 'browseHistory') {
          BrowseHistoryPanel()
        } else if (this.topActivity.screen.type === 'messages') {
          MessageListPanel({ composeToInit: this.topActivity.screen.composeTo })
        } else if (this.topActivity.screen.type === 'notifications') {
          NotificationPanel()
        } else if (this.topActivity.screen.type === 'topicList') {
          TopicListPanel({
            boardFid: this.topActivity.screen.topicListFid,
            boardName: this.topActivity.screen.topicListName,
            isFavorites: this.topActivity.screen.topicListFavor === '1',
            authorid: this.topActivity.screen.topicListAuthorid,
            favor: this.topActivity.screen.topicListFavor,
            searchpost: this.topActivity.screen.topicListSearchpost
          })
        } else {
          Stack() {
            Column() {
              Row().width('100%').height(44 + this.statusBarHeight)
              Column() {
                this.ContentBody()
              }
              .layoutWeight(1).width('100%')
            }
            .width('100%').height('100%')

            PanelNavBar({ title: this.topActivity.screen.getTitle() })
              .width('100%').position({ x: 0, y: 0 })
          }
          .width('100%').height('100%')
        }
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  ContentBody() {
    if (this.topActivity!.screen.type === 'profile') {
      ProfilePanel({ uid: this.topActivity!.screen.uid })
    } else if (this.topActivity!.screen.type === 'messageDetail') {
      MessageDetailPanel({ mid: this.topActivity!.screen.mid })
    } else if (this.topActivity!.screen.type === 'blacklist') {
      BlacklistPanel()
    } else if (this.topActivity!.screen.type === 'settings') {
      SettingsPanel()
    } else {
      Column() {
        Text('未知页面类型').fontSize(14).fontColor(AppColors.textTertiary)
      }
      .layoutWeight(1).width('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    }
  }
}
