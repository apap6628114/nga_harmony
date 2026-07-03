/**
 * AI 新手引导向导。
 *
 * 首次打开 AI 配置页面时弹出 4 步引导，
 * 用通俗语言解释 API 密钥是什么、如何获取、在哪填写。
 * 仅显示一次，之后可通过 "?" 按钮重新打开。
 */

import { AppColors } from '../../common/constants/Constants'

/** 引导步骤数据 */
class GuideStep {
  title: string
  content: string
  icon: string

  constructor(title: string, content: string, icon: string) {
    this.title = title
    this.content = content
    this.icon = icon
  }
}

const STEP1: GuideStep = new GuideStep(
  '什么是 API 密钥？',
  'API 密钥就像一把钥匙，让 App 能跟 AI 服务对话。\n\n你从 AI 服务商的网站获取它，然后在这里填好，App 就能用你自己的 AI 来总结帖子、分析用户了。\n\n就像你用密码登录账号一样简单。',
  '🔑'
)

const STEP2: GuideStep = new GuideStep(
  '需要花钱吗？',
  '大多数 AI 服务商会给新用户赠送免费额度。\n\n免费额度用完后按用量收费，价格通常很低。\n\nApp 只在你主动点击分析按钮时才调用 AI，不会在后台偷偷使用。放心使用！',
  '💡'
)

const STEP3: GuideStep = new GuideStep(
  '怎么获取 API 密钥？',
  '以 DeepSeek 为例：\n\n1. 浏览器打开 platform.deepseek.com\n2. 注册账号并登录\n3. 点击左侧「API Keys」菜单\n4. 创建新 Key 并复制\n\nOpenAI、智谱 GLM 等流程类似，都可以在官网找到入口。',
  '📋'
)

const STEP4: GuideStep = new GuideStep(
  '在哪填写？',
  '在 AI 配置页面：\n\n1. 选择服务商（地址自动填入）\n2. 粘贴你的 API 密钥\n3. 选择模型（或手动输入）\n4. 点击「测试连接」确认可用\n\n配置完成后，回到设置页切换即可使用你自己的 AI 了！',
  '✅'
)

/**
 * AI 新手引导向导组件。
 *
 * 以 @CustomDialog 形式展示引导内容，
 * 底部有步骤指示器和导航按钮。
 */
@CustomDialog
export struct AiSetupGuide {
  controller: CustomDialogController
  private currentStep: number = 0

  build() {
    Column() {
      // 标题行
      Text('AI 配置向导')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 4 })

      Text('第 ' + String(this.currentStep + 1) + ' 步 / 共 4 步')
        .fontSize(13)
        .fontColor(AppColors.textTertiary)
        .margin({ bottom: 12 })

      // 内容区域
      Column() {
        Text(this.currentStep === 0 ? STEP1.icon : (this.currentStep === 1 ? STEP2.icon : (this.currentStep === 2 ? STEP3.icon : STEP4.icon)))
          .fontSize(48)
          .margin({ bottom: 12 })

        Text(this.currentStep === 0 ? STEP1.title : (this.currentStep === 1 ? STEP2.title : (this.currentStep === 2 ? STEP3.title : STEP4.title)))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ bottom: 8 })
          .textAlign(TextAlign.Center)

        Text(this.currentStep === 0 ? STEP1.content : (this.currentStep === 1 ? STEP2.content : (this.currentStep === 2 ? STEP3.content : STEP4.content)))
          .fontSize(14)
          .fontColor(AppColors.textSecondary)
          .lineHeight(22)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24 })

      // 步骤指示点
      Row() {
        Text(this.currentStep === 0 ? '●' : '○')
          .fontSize(14)
          .fontColor(this.currentStep === 0 ? AppColors.primary : AppColors.separator)
          .margin({ left: 4, right: 4 })
        Text(this.currentStep === 1 ? '●' : '○')
          .fontSize(14)
          .fontColor(this.currentStep === 1 ? AppColors.primary : AppColors.separator)
          .margin({ left: 4, right: 4 })
        Text(this.currentStep === 2 ? '●' : '○')
          .fontSize(14)
          .fontColor(this.currentStep === 2 ? AppColors.primary : AppColors.separator)
          .margin({ left: 4, right: 4 })
        Text(this.currentStep === 3 ? '●' : '○')
          .fontSize(14)
          .fontColor(this.currentStep === 3 ? AppColors.primary : AppColors.separator)
          .margin({ left: 4, right: 4 })
      }
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 12 })

      // 底部按钮
      Row() {
        Text('上一步')
          .fontSize(15)
          .fontColor(this.currentStep > 0 ? AppColors.primary : AppColors.textTertiary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .onClick(() => {
            if (this.currentStep > 0) {
              this.currentStep = this.currentStep - 1
            }
          })

        Text(this.currentStep < 3 ? '下一步' : '完成')
          .fontSize(15)
          .fontColor(AppColors.primary)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .onClick(() => {
            if (this.currentStep < 3) {
              this.currentStep = this.currentStep + 1
            } else {
              this.controller.close()
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20, top: 4 })
    }
    .width('100%')
    .constraintSize({ minHeight: 380 })
    .backgroundColor(AppColors.bg)
    .borderRadius(16)
  }
}
