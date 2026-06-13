import { appStore } from '../store/AppStore'
import { AppColors } from './Constants'

/**
 * 视频播放组件（带全局静音切换）。
 *
 * 基于内置 Video 组件，在画面右上角叠加一个静音切换按钮。
 * 静音状态读取全局设置 videoMuted（通过 @StorageProp 响应式读取），
 * 点击按钮经 appStore.setVideoMuted 切换并持久化，所有 MutedVideo 实例同步生效。
 */
@Component
export struct MutedVideo {
  /** 视频源地址 */
  @Prop src: string = ''
  /** 视频宽高比（width / height），由调用方按已有尺寸缓存计算后传入 */
  @Prop videoAspectRatio: number = 1.78
  /** 全局视频静音状态：false=有声，true=静音 */
  @StorageProp('videoMuted') videoMuted: boolean = false

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Video({ src: this.src })
        .width('100%')
        .aspectRatio(this.videoAspectRatio)
        .objectFit(ImageFit.Contain)
        .controls(true)
        .autoPlay(false)
        .muted(this.videoMuted)
        .borderRadius(8)
        .backgroundColor(AppColors.bgSecondary)

      // 右上角静音切换按钮：静音态显示 icon_volume_off，有声态显示 icon_volume_up
      Stack() {
        Image(this.videoMuted ? $r('app.media.icon_volume_off') : $r('app.media.icon_volume_up'))
          .width(16).height(16).fillColor(AppColors.white)
      }
      .width(30).height(30).borderRadius(15)
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .margin({ top: 8, right: 8 })
      .onClick(() => {
        appStore.setVideoMuted(!this.videoMuted)
      })
    }
  }
}
