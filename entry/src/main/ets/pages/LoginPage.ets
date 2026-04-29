/**
 * 登录页面 - 从 React LoginPage.tsx 迁移
 * 支持两步登录：密码 → 验证码
 */

import { loginStep1, loginStep2, getCurrentUser } from '../service/NgaApi'
import { appStore } from '../store/AppStore'
import { AppColors } from '../common/Constants'
import router from '@ohos.router'

@Entry
@Component
struct LoginPage {
  @State username: string = ''
  @State password: string = ''
  @State captcha: string = ''
  @State loading: boolean = false
  @State error: string = ''
  @State loginToken: string = ''
  @State captchaId: string = ''
  @State captchaImage: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('themeName') themeName: string = 'original'

  build() {
    Column() {
      Text('N G A')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(12)
        .margin({ top: 120, bottom: 50 })

      TextInput({ placeholder: '用户名', text: this.username })
        .width('85%')
        .height(48)
        .fontSize(17)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(10)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.username = value
        })

      TextInput({ placeholder: '密码', text: this.password })
        .type(InputType.Password)
        .width('85%')
        .height(48)
        .fontSize(17)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(10)
        .padding({ left: 16, right: 16 })
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.password = value
        })

      if (this.loginToken) {
        Text('输入图形验证码(6字符)')
          .fontSize(13)
          .fontColor(AppColors.textTertiary)
          .margin({ top: 16 })

        Row() {
          TextInput({ placeholder: '验证码', text: this.captcha })
            .layoutWeight(1)
            .height(46)
            .fontSize(17)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(10)
            .padding({ left: 16, right: 16 })
            .maxLength(6)
            .onChange((value: string) => {
              this.captcha = value
            })

          if (this.captchaImage) {
            Image(this.captchaImage)
              .width(120)
              .height(46)
              .borderRadius(10)
              .backgroundColor(AppColors.bgSecondary)
              .objectFit(ImageFit.Contain)
              .margin({ left: 8 })
              .onClick(() => {
                this.refreshCaptcha()
              })
          }
        }
        .width('85%')
        .margin({ top: 12 })
      }

      if (this.error) {
        Text(this.error)
          .fontSize(13)
          .fontColor(AppColors.destructive)
          .margin({ top: 12 })
          .textAlign(TextAlign.Center)
      }

      Button(this.loading ? '...' : (this.loginToken ? '继 续' : '登 录'))
        .width('85%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.white)
        .backgroundColor(AppColors.primary)
        .borderRadius(12)
        .margin({ top: 20 })
        .enabled(!this.loading)
        .onClick(() => {
          this.handleLogin()
        })

      Row() {
        Divider().layoutWeight(1).color(AppColors.separator)
        Text('或').fontSize(11).fontColor(AppColors.textTertiary).padding({ left: 8, right: 8 })
        Divider().layoutWeight(1).color(AppColors.separator)
      }
      .width('85%')
      .margin({ top: 24, bottom: 24 })

      Text('鸿蒙端暂不支持凭据文件注入')
        .fontSize(13)
        .fontColor(AppColors.textTertiary)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgSecondary)
    .padding({ top: this.statusBarHeight })
    .alignItems(HorizontalAlign.Center)
  }

  private async handleLogin(): Promise<void> {
    this.error = ''

    if (!this.username || !this.password) {
      this.error = '请输入用户名和密码'
      return
    }

    this.loading = true

    try {
      if (this.loginToken) {
        // Step 2: 验证码登录
        if (!this.captcha) {
          this.error = '请输入验证码'
          this.loading = false
          return
        }

        const result = await loginStep2(this.loginToken, this.captchaId, this.captcha)

        if (result.ok && result.token) {
          // 登录成功
          const user = result.user!
          await appStore.setAuth(result.token, user.uid, user.nickName, user.avatarUrl)
          router.replaceUrl({ url: 'pages/MainPage' })
        } else if (result.needCaptcha) {
          // 需要重新输入验证码
          this.loginToken = result.loginToken
          this.captchaId = result.captchaId
          this.captchaImage = result.captchaImage
          this.error = result.error
          this.captcha = ''
        } else {
          this.error = result.error || '登录失败'
        }
      } else {
        // Step 1: 密码登录
        const result = await loginStep1(this.username, this.password)

        if (result.ok && result.needCaptcha) {
          this.loginToken = result.loginToken
          this.captchaId = result.captchaId
          this.captchaImage = result.captchaImage
        } else if (result.ok) {
          // 无需验证码直接登录（一般不会发生）
          this.error = result.error || '登录失败'
        } else {
          this.error = result.error || '登录失败'
        }
      }
    } catch (e) {
      this.error = (e as Error).message || '网络错误'
    } finally {
      this.loading = false
    }
  }

  private async refreshCaptcha(): Promise<void> {
    // 重新获取验证码 - 复用 loginStep1 的逻辑
    try {
      const result = await loginStep1(this.username, this.password)
      if (result.ok) {
        this.loginToken = result.loginToken
        this.captchaId = result.captchaId
        this.captchaImage = result.captchaImage
        this.captcha = ''
      }
    } catch (e) {
      // ignore
    }
  }
}
