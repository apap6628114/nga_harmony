import { appStore } from '../../store/AppStore'
import { AppColors, ImageLoadStrategy } from '../constants/Constants'
import { isWifiConnected } from '../utils/NetworkUtil'

/**
 * 视频播放组件（带全局静音切换）。
 *
 * 基于内置 Video 组件，在画面右上角叠加一个静音切换按钮。
 * 静音状态读取全局设置 videoMuted（通过 @StorageProp 响应式读取），
 * 点击按钮经 appStore.setVideoMuted 切换并持久化，所有 MutedVideo 实例同步生效。
 *
 * 通过 posterOptions.showFirstFrame 控制首帧送显（API 18+）：组件挂载后自动解码并显示
 * 视频真实首帧（替代默认黑屏），autoPlay(false) 不自动播放，等待用户点击播放键。
 * 是否送显首帧跟随图片加载策略，与图片主动加载条件一致——ALWAYS 或 WIFI_ONLY+WiFi 时
 * 启用首帧，MANUAL 或 WIFI_ONLY+非WiFi 时保持黑屏（见 shouldShowFirstFrame）。
 * 开启首帧送显后 previewUri 不生效（本组件未使用）。
 */
@Component
export struct MutedVideo {
  /** 视频源地址 */
  @Prop src: string = ''
  /** 视频宽高比（width / height），由调用方按已有尺寸缓存计算后传入 */
  @Prop videoAspectRatio: number = 1.78
  /** 全局视频静音状态：false=有声，true=静音 */
  @StorageProp('videoMuted') videoMuted: boolean = false
  /** 图片加载策略，订阅 AppStorage，决定首帧送显是否启用（与图片主动加载条件一致） */
  @StorageProp('imageLoadStrategy') imageLoadStrategy: string = ImageLoadStrategy.ALWAYS
  /** 网络变化版本号，订阅 AppStorage，WiFi/蜂窝切换时触发首帧送显重算 */
  @StorageProp('networkChangeVersion') networkChangeVersion: number = 0

  /**
   * 首帧送显是否启用：与图片主动加载条件一致（即 shouldUsePassive 的反面）。
   * ALWAYS 或 WIFI_ONLY+WiFi 时图片主动加载 → 启用首帧；
   * MANUAL 或 WIFI_ONLY+非WiFi 时图片被动加载 → 保持黑屏。
   *
   * @returns true=播放前送显首帧，false=保持黑屏
   */
  private shouldShowFirstFrame(): boolean {
    const strategy: string = this.imageLoadStrategy
    if (strategy === ImageLoadStrategy.ALWAYS) return true
    if (strategy === ImageLoadStrategy.MANUAL) return false
    return isWifiConnected()
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Video({
        src: this.src,
        // 首帧送显跟随图片加载策略：图片主动加载时送显首帧，否则保持黑屏（API 18+）
        posterOptions: { showFirstFrame: this.shouldShowFirstFrame() }
      })
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
