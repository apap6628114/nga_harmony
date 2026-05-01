import { routerStore } from '../store/RouterStore'
import { AppColors } from './Constants'

@Component
export struct PanelNavBar {
  @Prop title: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  onBack?: () => void
  @Prop showBack: boolean = true
  @Prop rightLabel: string = ''
  @Prop rightLabelColor: string = ''
  onRightClick?: () => void
  @Prop rightIcon?: Resource
  @Prop rightIconColor: string = ''

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
        Image(this.rightIcon).width(18).height(18).fillColor(this.rightIconColor || AppColors.primary)
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
    .backgroundColor('rgba(255, 255, 255, 255.0)')
    .backdropBlur(30)
    .border({ width: { bottom: 0.5 }, color: AppColors.separator }).alignItems(VerticalAlign.Center)
  }
}
