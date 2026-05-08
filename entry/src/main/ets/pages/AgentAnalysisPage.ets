import router from '@ohos.router'
import { FunctionComponent, FunctionController } from '@kit.AgentFrameworkKit'
import { pasteboard, BusinessError } from '@kit.BasicServicesKit'
import { appStore } from '../store/AppStore'
import { AppColors } from '../common/Constants'
import { UserActivityAnalysis, ForumStat } from '../service/NgaApi'

const AGENT_ID: string = 'agent1f869c42e32d4b6688b5f6d582fb2053'

@Entry
@Component
struct AgentAnalysisPage {
  private agentController: FunctionController = new FunctionController()
  @State analysisData: UserActivityAnalysis = new UserActivityAnalysis()
  @State profileName: string = ''
  @State targetUid: string = ''

  aboutToAppear(): void {
    const params: Record<string, Object> = router.getParams() as Record<string, Object>
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
        .onClick(() => router.back())
      }
      .width('100%')
      .padding({ top: 48, bottom: 8, left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          // 活跃概况
          Row() {
            this.SummaryBadge(String(this.analysisData.topicCount), '主题')
            this.SummaryBadge(String(this.analysisData.replyCount), '回复')
            this.SummaryBadge(String(this.analysisData.topicCount + this.analysisData.replyCount), '总计')
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

          // 活跃版面
          Text('活跃版面').fontSize(14).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Medium)
            .margin({ top: 14, bottom: 4 }).padding({ left: 16 })
          Column() {
            ForEach(this.getTopForums(), (fs: ForumStat) => {
              this.ForumRow(fs.name, fs.topicCount + fs.replyCount,
                Math.round((fs.topicCount + fs.replyCount) / Math.max(1, this.getTotalActivity()) * 100))
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 时间分布
          Text('发帖时段').fontSize(14).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Medium)
            .margin({ top: 10, bottom: 4 }).padding({ left: 12 })
          Column() {
            this.TimeSlot('凌晨 0-6时', this.getTimeSum(0, 5))
            this.TimeSlot('上午 6-12时', this.getTimeSum(6, 11))
            this.TimeSlot('下午 12-18时', this.getTimeSum(12, 17))
            this.TimeSlot('晚上 18-24时', this.getTimeSum(18, 23))
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 操作按钮
          Row() {
            Text('复制数据')
              .fontSize(14).fontColor(AppColors.white)
              .backgroundColor(AppColors.primary)
              .borderRadius(12)
              .padding({ left: 20, right: 20, top: 9, bottom: 9 })
              .onClick(() => {
                this.copyToClipboard(this.buildSummaryText())
              })

            FunctionComponent({
              agentId: AGENT_ID,
              onError: (err: BusinessError) => {
                console.error(`Agent launch failed: code=${err.code}, message=${err.message}`)
              },
              options: {
                title: 'AI分析',
                queryText: this.buildSummaryText()
              },
              controller: this.agentController
            })
          }
          .margin({ top: 14, bottom: 12, left: 16 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
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
      Text(label).fontSize(12).fontColor(AppColors.textSecondary).width(90)
      Row() {
        Text('').width(this.getBarWidth(count)).height(9).backgroundColor(AppColors.primary).borderRadius(4)
      }
      .width(80).height(9).backgroundColor(AppColors.bgSecondary).borderRadius(4)
      Text(String(count)).fontSize(12).fontColor(AppColors.textSecondary).margin({ left: 6 }).width(24)
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
  }

  private getTopForums(): ForumStat[] {
    return this.analysisData.forumList.slice(0, 5)
  }

  private getTotalActivity(): number {
    return this.analysisData.topicCount + this.analysisData.replyCount
  }

  private getBarWidth(count: number): number {
    const maxVal: number = this.getMaxTimeSlot()
    return maxVal > 0 ? Math.round(count / maxVal * 80) : 0
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
