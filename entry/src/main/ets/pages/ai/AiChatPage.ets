import { ChatMessage } from '../../service/ai/OpenAiCompatibleClient'
import { chatCompleteWithActiveAiStream, formatAiCompletionError } from '../../service/ai/ActiveAiService'
import { MdContentView } from '../../common/components/MdContentView'
import { MdStreamingContentView } from '../../common/components/MdStreamingContentView'
import { PanelNavBar } from '../../common/components/PanelNavBar'
import { AppColors } from '../../common/constants/Constants'

/** 流式输出刷新间隔毫秒数。 */
const STREAM_FLUSH_INTERVAL_MS: number = 80

/**
 * 聊天气泡。
 *
 * 每条气泡代表对话中的一轮发言。isStreaming 为 true 时
 * 表示 AI 仍在生成中，UI 应显示加载动画。
 */
class ChatBubble {
  /** 发言角色 */
  role: string = 'user'
  /** 消息内容（用户为纯文本，AI 为 Markdown） */
  content: string = ''
  /** AI 是否仍在流式生成中 */
  isStreaming: boolean = false

  constructor(role: string, content: string, isStreaming: boolean) {
    this.role = role
    this.content = content
    this.isStreaming = isStreaming
  }
}

/**
 * AI 对话页 — ChatGPT 式流式聊天界面。
 *
 * 支持预填充初始问题和连续多轮对话，可用于帖子总结和用户分析等场景。
 *
 * 路由参数：
 * - initialPrompt: string — 预填充的第一条用户消息
 * - title: string — 导航栏标题
 */
@Entry
@Component
struct AiChatPage {
  /** 对话气泡列表 */
  @State private bubbles: ChatBubble[] = []
  /** 输入框文本 */
  @State private inputText: string = ''
  /** 是否正在等待 AI 响应 */
  @State private isSending: boolean = false
  /** AI 流式输出当前累积文本（渲染用） */
  @State private streamingText: string = ''
  /** 导航栏标题 */
  @State private title: string = 'AI 对话'
  /** 初始 prompt */
  private initialPrompt: string = ''
  /** 流式输出完整缓冲，普通字段更新不会触发 ArkUI 重建。 */
  private streamBuffer: string = ''
  /** 流式输出刷新定时器句柄。 */
  private streamFlushTimer: number = -1

  /** 滚动控制器 */
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    const params: Record<string, Object> = this.getUIContext().getRouter().getParams() as Record<string, Object>
    if (params) {
      const prompt: string = (params['initialPrompt'] as string) ?? ''
      const t: string = (params['title'] as string) ?? ''
      this.initialPrompt = prompt
      if (t.length > 0) {
        this.title = t
      }
    }
    if (this.initialPrompt.length > 0) {
      this.sendMessage(this.initialPrompt)
    }
  }

  aboutToDisappear(): void {
    this.clearStreamingFlushTimer()
  }

  /**
   * 发送一条用户消息并获取 AI 回复。
   *
   * @param text - 用户输入的文本
   */
  private async sendMessage(text: string): Promise<void> {
    if (text.trim().length === 0) {
      return
    }

    const userBubble: ChatBubble = new ChatBubble('user', text, false)
    this.bubbles.push(userBubble)
    this.inputText = ''
    this.isSending = true
    this.resetStreamingState()

    // 构建对话历史（不含正在生成的 AI 回复）
    const history: ChatMessage[] = this.buildHistory()

    this.scrollToBottom()

    try {
      const finalText: string = await chatCompleteWithActiveAiStream(history, (chunk: string): void => {
        this.appendStreamingChunk(chunk)
      })
      this.flushStreamingText()
      // 流式完成 — 添加完整的 AI 气泡
      const aiBubble: ChatBubble = new ChatBubble('assistant', finalText, false)
      this.bubbles.push(aiBubble)
    } catch (err) {
      const e: Error = err as Error
      const errorText: string = formatAiCompletionError(e)
      const aiBubble: ChatBubble = new ChatBubble('assistant', errorText, false)
      this.bubbles.push(aiBubble)
    }

    this.resetStreamingState()
    this.isSending = false
    this.scrollToBottom()
  }

  /**
   * 追加 AI 流式文本增量并安排一次低频 UI 刷新。
   *
   * @param chunk - 本次收到的文本增量
   */
  private appendStreamingChunk(chunk: string): void {
    if (chunk.length === 0) {
      return
    }
    this.streamBuffer += chunk
    this.scheduleStreamingFlush()
  }

  /**
   * 安排流式文本刷新，避免每个网络 chunk 都触发 ArkUI 重建。
   */
  private scheduleStreamingFlush(): void {
    if (this.streamFlushTimer >= 0) {
      return
    }
    this.streamFlushTimer = setTimeout((): void => {
      this.streamFlushTimer = -1
      this.flushStreamingText()
    }, STREAM_FLUSH_INTERVAL_MS)
  }

  /**
   * 将普通字段缓冲同步到响应式状态。
   */
  private flushStreamingText(): void {
    if (this.streamingText === this.streamBuffer) {
      return
    }
    this.streamingText = this.streamBuffer
    this.scrollToBottom()
  }

  /**
   * 清理尚未执行的流式刷新定时器。
   */
  private clearStreamingFlushTimer(): void {
    if (this.streamFlushTimer < 0) {
      return
    }
    clearTimeout(this.streamFlushTimer)
    this.streamFlushTimer = -1
  }

  /**
   * 重置流式输出状态与缓冲。
   */
  private resetStreamingState(): void {
    this.clearStreamingFlushTimer()
    this.streamBuffer = ''
    this.streamingText = ''
  }

  /**
   * 从已完成的对话气泡中构建 ChatMessage 数组。
   *
   * @returns API 调用的对话历史
   */
  private buildHistory(): ChatMessage[] {
    const messages: ChatMessage[] = []
    for (let i: number = 0; i < this.bubbles.length; i++) {
      const b: ChatBubble = this.bubbles[i]
      if (b.role === 'user') {
        messages.push(new ChatMessage('user', b.content))
      } else if (b.role === 'assistant' && !b.isStreaming && b.content.length > 0) {
        messages.push(new ChatMessage('assistant', b.content))
      }
    }
    return messages
  }

  /** 滚动到底部。 */
  private scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom)
  }

  build() {
    Column() {
      // 导航栏
      PanelNavBar({
        title: this.title,
        showBack: true,
        onBack: (): void => { this.getUIContext().getRouter().back() }
      })

      // 对话区
      Scroll(this.scroller) {
        Column() {
          ForEach(this.bubbles, (bubble: ChatBubble, index: number) => {
            this.RenderBubble(bubble)
          }, (bubble: ChatBubble, index: number) => 'cb_' + index.toString())

          // 流式 AI 气泡 — MdContentView 直接读 @State，不通过 @Builder 参数！
          if (this.isSending && this.streamingText.length > 0) {
            Row() {
              Column() {
                MdStreamingContentView({ text: this.streamingText })
                Row() {
                  LoadingProgress()
                    .width(16).height(16)
                    .color(AppColors.primary)
                }
                .margin({ top: 6 })
              }
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius({ topLeft: 4, topRight: 14, bottomLeft: 14, bottomRight: 14 })
              .width('100%')
              .constraintSize({ maxWidth: '85%' })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .margin({ top: 6, bottom: 6 })
            .alignItems(VerticalAlign.Top)
          } else if (this.isSending && this.streamingText.length === 0) {
            Row() {
              Column() {
                Row() {
                  LoadingProgress()
                    .width(20).height(20)
                    .color(AppColors.primary)
                  Text('  AI 思考中...')
                    .fontSize(14)
                    .fontColor(AppColors.textSecondary)
                }
              }
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius({ topLeft: 4, topRight: 14, bottomLeft: 14, bottomRight: 14 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .margin({ top: 6, bottom: 6 })
            .alignItems(VerticalAlign.Top)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)

      // 底部输入栏
      this.RenderInputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bg)
  }

  // ============================================================
  // 气泡渲染
  // ============================================================

  /** 渲染单条已完成的聊天气泡。 */
  @Builder
  RenderBubble(bubble: ChatBubble) {
    Row() {
      if (bubble.role === 'user') {
        // 用户气泡：紧凑包裹文字，右对齐
        Column() {
          Text(bubble.content)
            .fontSize(15)
            .fontColor(AppColors.white)
            .lineHeight(24)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(AppColors.primary)
        .borderRadius({ topLeft: 14, topRight: 4, bottomLeft: 14, bottomRight: 14 })
        .constraintSize({ maxWidth: '80%' })
      } else {
        // AI 气泡：撑满宽度（给 MdContentView 确定宽度上下文），左对齐
        Column() {
          MdContentView({ text: bubble.content })
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius({ topLeft: 4, topRight: 14, bottomLeft: 14, bottomRight: 14 })
        .width('100%')
        .constraintSize({ maxWidth: '85%' })
      }
    }
    .width('100%')
    .justifyContent(bubble.role === 'user' ? FlexAlign.End : FlexAlign.Start)
    .margin({ top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Top)
  }

  // ============================================================
  // 底部输入栏
  // ============================================================

  /** 渲染底部输入栏。 */
  @Builder
  RenderInputBar() {
    Row() {
      TextInput({ text: this.inputText, placeholder: '输入追问内容...' })
        .layoutWeight(1)
        .fontSize(15)
        .borderRadius(20)
        .backgroundColor(AppColors.bgSecondary)
        .height(40)
        .padding({ left: 16, right: 16 })
        .onChange((value: string): void => {
          this.inputText = value
        })
        .onSubmit((): void => {
          this.sendMessage(this.inputText)
        })
      Button('发送')
        .fontSize(14)
        .fontColor(AppColors.white)
        .backgroundColor(AppColors.primary)
        .borderRadius(20)
        .height(40)
        .padding({ left: 18, right: 18 })
        .margin({ left: 8 })
        .enabled(!this.isSending && this.inputText.trim().length > 0)
        .onClick((): void => {
          this.sendMessage(this.inputText)
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(AppColors.bg)
    .border({ width: { top: 0.5 }, color: AppColors.separator })
    .alignItems(VerticalAlign.Center)
  }
}
