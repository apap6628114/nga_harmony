import { routerStore } from '../store/RouterStore'
import { AppColors } from './Constants'

@Component
export struct PanelNavBar {
  @Prop title: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  onBack?: () => void
  @Prop showBack: boolean = true
  @Prop rightLabel: string = ''
  @Prop rightLabelColor: ResourceColor = ''
  onRightClick?: () => void
  @Prop rightIcon?: Resource
  @Prop rightIconColor: string = ''
  @Prop rightIconBadge: number = 0

  build() {
    Row() {
      if (this.showBack) {
        Row() {
          Image($r('app.media.icon_back')).width(22).height(22).objectFit(ImageFit.Contain).fillColor(AppColors.primary)
        }
        .padding({ left: 8, right: 8 })
        .onClick(() => { if (this.onBack) { this.onBack() } else { routerStore.back() } })
      } else {
        Blank().width(16)
      }

      Text(this.title).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.rightIcon) {
        Stack() {
          Image(this.rightIcon).width(18).height(18).fillColor(this.rightIconColor || AppColors.primary)
          if (this.rightIconBadge > 0) {
            Text(this.rightIconBadge > 99 ? '99+' : String(this.rightIconBadge))
              .fontSize(9).fontColor(Color.White).textAlign(TextAlign.Center)
              .height(16).borderRadius(8).backgroundColor(Color.Red)
              .padding({ left: 5, right: 5 })
              .position({ x: 13, y: -5 })
          }
        }
        .width(28).height(22)
        .margin({ right: 16 })
        .onClick(() => { if (this.onRightClick) { this.onRightClick() } })
      } else if (this.rightLabel) {
        Text(this.rightLabel).fontSize(14)
          .fontColor(this.rightLabelColor || AppColors.primary)
          .onClick(() => { if (this.onRightClick) { this.onRightClick() } })
          .padding({ left: 8, right: 16 })
      } else {
        Blank().width(70)
      }
    }
    .width('100%').height(44 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .backgroundEffect({
      radius: 30,
      saturation: 1.15,
      brightness: 1.08,
      color: AppColors.frostGlassStrong
    })
    .border({ width: { bottom: 0.5 }, color: AppColors.separator }).alignItems(VerticalAlign.Center)
  }
}
