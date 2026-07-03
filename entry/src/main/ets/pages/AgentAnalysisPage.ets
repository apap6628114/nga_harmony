
import { pasteboard } from '@kit.BasicServicesKit'
import { appStore } from '../store/AppStore'
import { AppColors } from '../common/constants/Constants'
import { UserActivityAnalysis, ForumStat } from '../model/NgaApiResults'
import { ToastComponent } from '../common/components/Toast'
import { Logger, DOMAIN_UI } from '../common/utils/Logger'
import type { AiProviderProfile } from '../model/AiConfig'
import { ChatMessage, chatComplete } from '../service/ai/OpenAiCompatibleClient'
import { translateError } from '../service/ai/AiErrorTranslator'

const logger = new Logger(DOMAIN_UI, 'AgentAnalysis')

@Entry
@Component
struct AgentAnalysisPage {
  @State analysisData: UserActivityAnalysis = new UserActivityAnalysis()
  @State profileName: string = ''
  @State targetUid: string = ''
  @State customAiText: string = ''
  @State customAiLoading: boolean = false
  @State customAiError: string = ''

  aboutToAppear(): void {
    const params: Record<string, Object> = this.getUIContext().getRouter().getParams() as Record<string, Object>
    if (params) {
      const raw = params['analysisData'] as string
      if (raw) {
        this.analysisData = this.parseAnalysisData(JSON.parse(raw))
      }
      this.profileName = (params['profileName'] as string) ?? ''
      this.targetUid = (params['targetUid'] as string) ?? ''
    }
  }

  private parseAnalysisData(raw: Record<string, Object>): UserActivityAnalysis {
    const d: UserActivityAnalysis = new UserActivityAnalysis()
    d.topicCount = (raw['topicCount'] as number) ?? 0
    d.replyCount = (raw['replyCount'] as number) ?? 0
    d.topicSubjects = (raw['topicSubjects'] as string[]) ?? []
    d.replySnippets = (raw['replySnippets'] as string[]) ?? []
    d.hourDistribution = (raw['hourDistribution'] as number[]) ?? []
    const forumRaw: Record<string, Object>[] = (raw['forumList'] as Record<string, Object>[]) ?? []
    d.forumList = []
    for (let i = 0; i < forumRaw.length; i++) {
      const f: ForumStat = new ForumStat()
      f.name = String(forumRaw[i]['name'] ?? '')
      f.topicCount = Number(forumRaw[i]['topicCount'] ?? 0)
      f.replyCount = Number(forumRaw[i]['replyCount'] ?? 0)
      d.forumList.push(f)
    }
    return d
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('账号成分分析')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1)

          Button() {
            Image($r('app.media.icon_close'))
              .width(18).height(18)
              .fillColor(AppColors.textPrimary)
          }
          .width(32).height(32)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(16)
          .onClick(() => this.getUIContext().getRouter().back())
        }
        .width('100%')
        .padding({ top: 48, bottom: 8, left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            Row() {
              this.SummaryBadge(String(this.analysisData.topicCount), '主题')
              this.SummaryBadge(String(this.analysisData.replyCount), '回复')
              this.SummaryBadge(String(this.analysisData.topicCount + this.analysisData.replyCount), '总计')
            }
            .width('100%')
            .padding({ top: 8 })
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(10)

            Text('活跃版面')
              .fontSize(14)
              .fontColor(AppColors.textPrimary)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 14, bottom: 4 })
            Column() {
              ForEach(this.getTopForums(), (fs: ForumStat) => {
                this.ForumRow(fs.name, fs.topicCount + fs.replyCount,
                  Math.round((fs.topicCount + fs.replyCount) / Math.max(1, this.getTotalActivity()) * 100))
              })
            }
            .width('100%')

            Text('发帖时段')
              .fontSize(14)
              .fontColor(AppColors.textPrimary)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 10, bottom: 4 })
            Column() {
              this.TimeSlot('凌晨 0-6时', this.getTimeSum(0, 5))
              this.TimeSlot('上午 6-12时', this.getTimeSum(6, 11))
              this.TimeSlot('下午 12-18时', this.getTimeSum(12, 17))
              this.TimeSlot('晚上 18-24时', this.getTimeSum(18, 23))
            }
            .width('100%')

            Row() {
              Text('复制数据')
                .fontSize(14).fontColor(AppColors.white)
                .backgroundColor(AppColors.primary)
                .borderRadius(12)
                .padding({ left: 20, right: 20, top: 9, bottom: 9 })
                .onClick(() => {
                  this.copyToClipboard(this.buildSummaryText())
                })

              Text(this.customAiLoading ? 'AI 分析中...' : 'AI 分析')
                .fontSize(14).fontColor(AppColors.white)
                .backgroundColor(AppColors.primary)
                .borderRadius(12)
                .padding({ left: 20, right: 20, top: 9, bottom: 9 })
                .margin({ left: 12 })
                .onClick(() => {
                  if (!this.customAiLoading) {
                    this.startCustomAiAnalysis()
                  }
                })
            }
            .margin({ top: 14, bottom: 12 })

            // 自定义 AI 结果展示区
            if (this.customAiText.length > 0 || this.customAiError.length > 0 || this.customAiLoading) {
              Column() {
                Text('AI 分析结果')
                  .fontSize(13)
                  .fontColor(AppColors.textTertiary)
                  .fontWeight(FontWeight.Medium)
                  .margin({ bottom: 6 })

                if (this.customAiLoading) {
                  Row() {
                    LoadingProgress()
                      .width(20).height(20)
                      .color(AppColors.primary)
                    Text('  AI 正在分析...')
                      .fontSize(14)
                      .fontColor(AppColors.textSecondary)
                  }
                  .margin({ top: 12, bottom: 12 })
                }

                if (this.customAiText.length > 0) {
                  Text(this.customAiText)
                    .fontSize(14)
                    .fontColor(AppColors.textPrimary)
                    .width('100%')
                    .lineHeight(22)

                  Row() {
                    Text('复制结果')
                      .fontSize(13)
                      .fontColor(AppColors.primary)
                      .onClick(() => {
                        this.copyToClipboard(this.customAiText)
                      })
                  }
                  .margin({ top: 8 })
                }

                if (this.customAiError.length > 0) {
                  Text(this.customAiError)
                    .fontSize(13)
                    .fontColor(AppColors.destructive)
                    .width('100%')
                    .margin({ top: 8 })
                    .lineHeight(20)
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius(10)
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 10 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      ToastComponent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bg)
  }

  @Builder
  SummaryBadge(value: string, label: string) {
    Column() {
      Text(value).fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColors.primary)
      Text(label).fontSize(11).fontColor(AppColors.textTertiary).margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ForumRow(name: string, count: number, pct: number) {
    Row() {
      Text(name).fontSize(13).fontColor(AppColors.textPrimary).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(String(count)).fontSize(13).fontColor(AppColors.textSecondary).margin({ left: 4 })
      Row() {
        Text('').width(pct > 0 ? pct * 1.2 : 0).height(7).backgroundColor(AppColors.primary).borderRadius(3)
      }
      .width(120).height(7).backgroundColor(AppColors.bgSecondary).borderRadius(3).margin({ left: 6 })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  TimeSlot(label: string, count: number) {
    Row() {
      Text(label).fontSize(12).fontColor(AppColors.textSecondary).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(String(count)).fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 4 }).width(24)
        .textAlign(TextAlign.End)
      Row() {
        Text('').width(this.getBarWidth(count)).height(7).backgroundColor(AppColors.primary).borderRadius(3)
      }
      .width(120).height(7).backgroundColor(AppColors.bgSecondary).borderRadius(3).margin({ left: 6 })
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
    .alignItems(VerticalAlign.Center)
  }

  private getTopForums(): ForumStat[] {
    return this.analysisData.forumList.slice(0, 5)
  }

  private getTotalActivity(): number {
    return this.analysisData.topicCount + this.analysisData.replyCount
  }

  private getBarWidth(count: number): number {
    const maxVal: number = this.getMaxTimeSlot()
    return maxVal > 0 ? Math.round(count / maxVal * 120) : 0
  }

  private getTimeSum(start: number, end: number): number {
    let sum: number = 0
    for (let i: number = start; i <= end; i++) {
      sum += this.analysisData.hourDistribution[i] || 0
    }
    return sum
  }

  private getMaxTimeSlot(): number {
    const a: number = this.getTimeSum(0, 5)
    const b: number = this.getTimeSum(6, 11)
    const c: number = this.getTimeSum(12, 17)
    const d: number = this.getTimeSum(18, 23)
    return Math.max(a, b, c, d, 1)
  }

  private buildSummaryText(): string {
    const d: UserActivityAnalysis = this.analysisData
    let text: string = `${this.profileName}(UID:${this.targetUid}) 的账号分析：\n`
    text += `共 ${d.topicCount} 个主题，${d.replyCount} 条回复\n\n`
    text += '活跃版面：\n'
    for (let i: number = 0; i < d.forumList.length; i++) {
      const f: ForumStat = d.forumList[i]
      text += `  ${f.name}: ${f.topicCount + f.replyCount} 帖\n`
    }
    text += '\n发帖时段：\n'
    text += `  凌晨: ${this.getTimeSum(0, 5)} 帖\n`
    text += `  上午: ${this.getTimeSum(6, 11)} 帖\n`
    text += `  下午: ${this.getTimeSum(12, 17)} 帖\n`
    text += `  晚上: ${this.getTimeSum(18, 23)} 帖\n`
    if (d.topicSubjects.length > 0) {
      text += '\n发表的主题：\n'
      for (let i: number = 0; i < d.topicSubjects.length; i++) {
        text += `  ${i + 1}. ${d.topicSubjects[i]}\n`
      }
    }
    if (d.replySnippets.length > 0) {
      text += '\n回复内容：\n'
      for (let i: number = 0; i < d.replySnippets.length; i++) {
        text += `  ${i + 1}. ${d.replySnippets[i]}\n`
      }
    }
    text += '\n\n【分析指令】请根据以上用户的论坛活跃版面、发表主题和回复内容，分析总结以下内容：\n'
    text += '1. 用户画像：推断该用户的身份、兴趣领域、在论坛中的角色\n'
    text += '2. 政治光谱：根据其讨论话题和立场倾向，判断其政治倾向\n'
    text += '3. 整体点评：以辛辣尖锐的语言风格对其用户画像进行一句话锐评\n'
    return text
  }

  private async startCustomAiAnalysis(): Promise<void> {
    const idx: number = appStore.settings.activeAiConfigIndex
    const profiles: AiProviderProfile[] = appStore.settings.aiProfiles
    if (idx < 0 || idx >= profiles.length) {
      appStore.showToast('请先在设置中选择 AI 方案')
      return
    }

    const profile: AiProviderProfile = profiles[idx]
    if (!profile.apiKey || profile.apiKey.length === 0) {
      appStore.showToast('请先在 AI 配置中填写 API 密钥')
      return
    }

    this.customAiText = ''
    this.customAiError = ''
    this.customAiLoading = true

    try {
      const prompt: string = this.buildSummaryText()
      const messages: ChatMessage[] = []
      const userMsg: ChatMessage = new ChatMessage('user', prompt)
      messages[0] = userMsg

      const result: string = await chatComplete(profile, messages)
      this.customAiText = result
    } catch (err) {
      const e: Error = err as Error
      const code: number = parseInt(e.message)
      if (!isNaN(code)) {
        const info = translateError(code)
        this.customAiError = info.userMessage + '\n' + info.suggestion
      } else {
        this.customAiError = 'AI 调用失败：' + (e.message || '未知错误')
      }
    } finally {
      this.customAiLoading = false
    }
  }

  private async copyToClipboard(text: string): Promise<void> {
    try {
      const pb: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
      const record: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await pb.setData(record)
      appStore.showToast('已复制到剪贴板')
    } catch (e) {
      appStore.showToast('复制失败')
    }
  }
}
