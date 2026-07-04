
import { pasteboard } from '@kit.BasicServicesKit'
import { appStore } from '../store/AppStore'
import { AppColors } from '../common/constants/Constants'
import { ToastComponent } from '../common/components/Toast'
import { ChatMessage } from '../service/ai/OpenAiCompatibleClient'
import { chatCompleteWithActiveAiStream, formatAiCompletionError } from '../service/ai/ActiveAiService'

@Entry
@Component
struct PostSummaryPage {
  @State postContent: string = ''
  @State authorName: string = ''
  @State lou: number = 0
  @State threadSubject: string = ''
  @State aiResultText: string = ''
  @State aiLoading: boolean = false
  @State aiError: string = ''

  aboutToAppear(): void {
    const params: Record<string, Object> = this.getUIContext().getRouter().getParams() as Record<string, Object>
    if (params) {
      this.postContent = (params['postContent'] as string) ?? ''
      this.authorName = (params['authorName'] as string) ?? ''
      this.lou = (params['lou'] as number) ?? 0
      this.threadSubject = (params['threadSubject'] as string) ?? ''
    }
  }

  private buildSummaryPrompt(): string {
    let text: string = ''
    text += '【帖子信息】\n'
    text += `标题：${this.threadSubject}\n`
    text += `楼层：#${this.lou}  作者：${this.authorName}\n\n`
    text += '【正文内容】\n'
    text += this.postContent
    text += '\n\n'
    text += '【总结指令】请对以上帖子正文内容进行深度总结归纳：\n'
    text += '1. 核心观点：提取帖子的主要论点和立场\n'
    text += '2. 关键信息：列出重要的事实、数据或论据\n'
    text += '3. 逻辑脉络：梳理帖子的行文结构和论证逻辑\n'
    text += '4. 一句话总结：用精炼的语言概括帖子的核心内容'
    return text
  }

  private async startAiSummary(): Promise<void> {
    this.aiResultText = ''
    this.aiError = ''
    this.aiLoading = true

    try {
      const prompt: string = this.buildSummaryPrompt()
      const messages: ChatMessage[] = []
      const userMsg: ChatMessage = new ChatMessage('user', prompt)
      messages[0] = userMsg

      const result: string = await chatCompleteWithActiveAiStream(messages, (chunk: string): void => {
        this.aiResultText += chunk
      })
      if (this.aiResultText.length === 0) {
        this.aiResultText = result
      }
    } catch (err) {
      const e: Error = err as Error
      this.aiError = formatAiCompletionError(e)
    } finally {
      this.aiLoading = false
    }
  }


  build() {
    Stack() {
      Column() {
        Row() {
          Text('AI 内容总结')
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
            Column() {
              Row() {
                Text(`#${this.lou}`)
                  .fontSize(14)
                  .fontColor(AppColors.primary)
                  .fontWeight(FontWeight.Bold)
                Text(' · ')
                  .fontSize(14)
                  .fontColor(AppColors.textTertiary)
                Text(this.authorName)
                  .fontSize(14)
                  .fontColor(AppColors.textPrimary)
                  .fontWeight(FontWeight.Medium)
              }

              Text(this.threadSubject)
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
                .margin({ top: 4 })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .alignItems(HorizontalAlign.Start)

            Column() {
              Row() {
                Text('原文内容')
                  .fontSize(13)
                  .fontColor(AppColors.textTertiary)
                  .fontWeight(FontWeight.Medium)
                Text(`${this.postContent.length}字`)
                  .fontSize(11)
                  .fontColor(AppColors.textTertiary)
                  .margin({ left: 6 })
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .backgroundColor(AppColors.bgTertiary)
                  .borderRadius(4)
              }
              .margin({ bottom: 6 })

              Scroll() {
                Text(this.postContent)
                  .fontSize(14)
                  .fontColor(AppColors.textPrimary)
                  .width('100%')
                  .lineHeight(22)
              }
              .width('100%')
              .constraintSize({ maxHeight: 280 })
              .scrollBar(BarState.Auto)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(10)
            .alignItems(HorizontalAlign.Start)

            Row() {
              Text('复制原文')
                .fontSize(14).fontColor(AppColors.white)
                .backgroundColor(AppColors.primary)
                .borderRadius(12)
                .padding({ left: 20, right: 20, top: 9, bottom: 9 })
                .onClick(() => {
                  this.copyToClipboard(this.postContent)
                })

              Text(this.aiLoading ? 'AI 总结中...' : 'AI 总结')
                .fontSize(14).fontColor(AppColors.white)
                .backgroundColor(AppColors.primary)
                .borderRadius(12)
                .padding({ left: 20, right: 20, top: 9, bottom: 9 })
                .margin({ left: 12 })
                .onClick(() => {
                  if (!this.aiLoading) {
                    this.startAiSummary()
                  }
                })
            }
            .margin({ top: 14, bottom: 12 })

            if (this.aiResultText.length > 0 || this.aiError.length > 0 || this.aiLoading) {
              Column() {
                Text('AI 总结结果')
                  .fontSize(13)
                  .fontColor(AppColors.textTertiary)
                  .fontWeight(FontWeight.Medium)
                  .margin({ bottom: 6 })

                if (this.aiLoading) {
                  Row() {
                    LoadingProgress()
                      .width(20).height(20)
                      .color(AppColors.primary)
                    Text(this.aiResultText.length > 0 ? '  AI 正在生成...' : '  AI 正在分析...')
                      .fontSize(14)
                      .fontColor(AppColors.textSecondary)
                  }
                  .margin({ top: 12, bottom: 12 })
                }

                if (this.aiResultText.length > 0) {
                  Text(this.aiResultText)
                    .fontSize(14)
                    .fontColor(AppColors.textPrimary)
                    .width('100%')
                    .lineHeight(22)

                  Row() {
                    Text('复制结果')
                      .fontSize(13)
                      .fontColor(AppColors.primary)
                      .onClick(() => {
                        this.copyToClipboard(this.aiResultText)
                      })
                  }
                  .margin({ top: 8 })
                }

                if (this.aiError.length > 0) {
                  Text(this.aiError)
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
