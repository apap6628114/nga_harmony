import { AppColors } from '../constants/Constants'
import { MdContentView } from './MdContentView'

/** 流式 Markdown 拆分结果。 */
class MarkdownStreamSplit {
  /** 已经到达安全块边界的稳定 Markdown 前缀。 */
  stableText: string = ''
  /** 正在增长的尾部文本。 */
  tailText: string = ''
  /** 尾部文本是否位于未闭合代码块内。 */
  tailInCodeBlock: boolean = false
}

/**
 * Markdown 流式内容渲染组件。
 *
 * 稳定块使用完整 Markdown 渲染，正在增长的尾段使用轻量 Text 渲染，
 * 避免每次流式刷新都触发完整 Markdown 解析与整棵 AST 重建。
 */
@Component
export struct MdStreamingContentView {
  /** 原始流式 Markdown 文本。 */
  @Prop @Watch('onTextChange') text: string = ''
  /** 链接点击回调。 */
  onLinkClick: (href: string) => void = (_href: string) => {}

  /** 已稳定的 Markdown 前缀。 */
  @State private stableText: string = ''
  /** 正在增长的尾部文本。 */
  @State private tailText: string = ''
  /** 尾部文本是否处于未闭合代码块。 */
  @State private tailInCodeBlock: boolean = false

  /**
   * 组件出现时初始化拆分状态。
   */
  aboutToAppear(): void {
    this.updateSplitState()
  }

  /**
   * 文本变化时刷新稳定前缀与尾段。
   */
  private onTextChange(): void {
    this.updateSplitState()
  }

  /**
   * 根据当前文本计算并写入组件内部响应式状态。
   */
  private updateSplitState(): void {
    const split: MarkdownStreamSplit = splitStreamingMarkdown(this.text)
    if (this.stableText !== split.stableText) {
      this.stableText = split.stableText
    }
    if (this.tailText !== split.tailText) {
      this.tailText = split.tailText
    }
    if (this.tailInCodeBlock !== split.tailInCodeBlock) {
      this.tailInCodeBlock = split.tailInCodeBlock
    }
  }

  build() {
    Column() {
      if (this.stableText.length > 0) {
        MdContentView({
          text: this.stableText,
          onLinkClick: this.onLinkClick
        })
      }
      if (this.tailText.length > 0) {
        if (this.tailInCodeBlock) {
          this.RenderCodeTail()
        } else {
          this.RenderTextTail()
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 渲染普通尾段文本。
   */
  @Builder
  RenderTextTail() {
    Text(this.tailText)
      .fontSize(15)
      .fontColor(AppColors.textPrimary)
      .lineHeight(26)
      .width('100%')
      .margin({ top: 2, bottom: 6 })
  }

  /**
   * 渲染未闭合代码块尾段。
   */
  @Builder
  RenderCodeTail() {
    Scroll() {
      Text(this.tailText)
        .fontSize(13)
        .fontColor(AppColors.textPrimary)
        .fontFamily('monospace')
        .lineHeight(20)
        .padding(12)
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(8)
    .margin({ top: 6, bottom: 6 })
  }
}

/**
 * 将流式 Markdown 拆分为稳定前缀与不稳定尾段。
 *
 * @param text - 当前累计 Markdown 文本
 * @returns 拆分后的稳定前缀、尾部文本与代码块状态
 */
function splitStreamingMarkdown(text: string): MarkdownStreamSplit {
  const result: MarkdownStreamSplit = new MarkdownStreamSplit()
  if (text.length === 0) {
    return result
  }

  const normalized: string = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  let inCodeBlock: boolean = false
  let stableBoundary: number = 0
  let lineStart: number = 0
  let i: number = 0

  while (i <= normalized.length) {
    if (i < normalized.length && normalized.charAt(i) !== '\n') {
      i++
      continue
    }

    const line: string = normalized.substring(lineStart, i)
    const trimmedLine: string = line.trim()
    if (isFenceLine(trimmedLine)) {
      inCodeBlock = !inCodeBlock
    }
    if (!inCodeBlock && trimmedLine.length === 0) {
      stableBoundary = i < normalized.length ? i + 1 : i
    }
    lineStart = i + 1
    i++
  }

  result.stableText = normalized.substring(0, stableBoundary)
  result.tailText = normalized.substring(stableBoundary)
  result.tailInCodeBlock = inCodeBlock
  return result
}

/**
 * 判断一行是否为 Markdown 围栏代码标记。
 *
 * @param trimmedLine - 已经去除首尾空白的行文本
 * @returns 如果是围栏代码标记则返回 true
 */
function isFenceLine(trimmedLine: string): boolean {
  if (trimmedLine.indexOf('```') !== 0) {
    return false
  }
  const language: string = trimmedLine.substring(3).trim()
  if (language.length === 0) {
    return true
  }
  for (let i: number = 0; i < language.length; i++) {
    const ch: string = language.charAt(i)
    const isLower: boolean = ch >= 'a' && ch <= 'z'
    const isUpper: boolean = ch >= 'A' && ch <= 'Z'
    const isNumber: boolean = ch >= '0' && ch <= '9'
    if (!isLower && !isUpper && !isNumber && ch !== '_') {
      return false
    }
  }
  return true
}
