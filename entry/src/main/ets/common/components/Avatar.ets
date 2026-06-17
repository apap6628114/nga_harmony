/**
 * 头像组件 - 从 React Avatar.tsx 迁移
 * 支持图片加载失败时显示首字母
 */

import { AppColors, ImageLoadStrategy } from '../constants/Constants'
import { getAvatarUrl, nameToHue, hslToHex, getInitial } from '../utils/Utils'
import { shouldUsePassive } from '../utils/NetworkUtil'

@Component
export struct Avatar {
  @Prop avatar: string = ''
  @Prop uid: string = ''
  @Prop name: string = ''
  @Prop avatarSize: number = 40
  @State imgError: boolean = false
  /** 图片加载策略，订阅 AppStorage，决定头像是否走被动占位 */
  @StorageProp('imageLoadStrategy') imageLoadStrategy: string = ImageLoadStrategy.ALWAYS
  /** 网络变化版本号，订阅 AppStorage，WiFi/蜂窝切换时触发重算 */
  @StorageProp('networkChangeVersion') networkChangeVersion: number = 0

  build() {
    Stack() {
      // 首字母：主动且有有效头像 URL 时隐藏（此时渲染真实图）；被动 / 无 URL / 出错时显示
      Text(getInitial(this.name))
        .fontSize(this.avatarSize * 0.4)
        .fontColor(AppColors.white)
        .fontWeight(FontWeight.Bold)
        .visibility(this.getAvatarUrlStr() && !this.imgError && !shouldUsePassive(this.imageLoadStrategy) ? Visibility.None : Visibility.Visible)

      // 头像图片：URL 有效、未出错、且非被动模式时渲染
      if (this.getAvatarUrlStr() && !this.imgError && !shouldUsePassive(this.imageLoadStrategy)) {
        Image(this.getAvatarUrlStr())
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .objectFit(ImageFit.Cover)
          .onError(() => {
            this.imgError = true
          })
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .backgroundColor(this.getBgColor())
  }

  private getAvatarUrlStr(): string {
    return getAvatarUrl(this.avatar, this.uid)
  }

  private getBgColor(): string {
    return hslToHex(nameToHue(this.name), 55, 55)
  }
}
