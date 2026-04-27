import { AppColors } from './Constants'

@Component
export struct EmptyHint {
  build() {
    Column() {
      Image($r('app.media.icon_chat_bubble')).width(48).height(48).opacity(0.3).margin({ bottom: 12 })
      Text('从左侧选择一个板块').fontSize(15).fontColor(AppColors.textTertiary)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.bg)
  }
}
