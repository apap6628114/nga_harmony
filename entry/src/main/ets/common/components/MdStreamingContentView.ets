import { MdNode } from '../../model/MdNode'
import { parseMd } from '../../parser/md/MdParser'
import { MdNodeDataSource } from '../datasource/MdNodeDataSource'
import { AppColors } from '../constants/Constants'
import { MdNodesView } from './MdNodesView'

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
 * 稳定块增量解析为 AST 并追加到数据源，正在增长的尾段使用轻量 Text 渲染。
 */
@Component
export struct MdStreamingContentView {
  /** 原始流式 Markdown 文本。 */
  @Prop @Watch('onTextChange') text: string = ''
  /** 链接点击回调。 */
  onLinkClick: (href: string) => void = (_href: string) => {}

  /** 已稳定的 Markdown AST 节点。 */
  @State private stableNodes: MdNode[] = []
  /** 正在增长的尾部文本。 */
  @State private tailText: string = ''
  /** 尾部文本是否处于未闭合代码块。 */
  @State private tailInCodeBlock: boolean = false
  /** 已消费的稳定前缀长度。 */
  private consumedStableLength: number = 0
  /** 稳定段序号，用于给增量解析结果补充唯一 key 前缀。 */
  private stableSegmentSerial: number = 0
  /** 稳定块 LazyForEach 数据源。 */
  private stableDataSource: MdNodeDataSource = new MdNodeDataSource()

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
    if (split.stableText.length < this.consumedStableLength) {
      this.resetStableNodes()
    }
    if (split.stableText.length > this.consumedStableLength) {
      const addedStableText: string = split.stableText.substring(this.consumedStableLength)
      this.appendStableText(addedStableText)
      this.consumedStableLength = split.stableText.length
    }
    if (this.tailText !== split.tailText) {
      this.tailText = split.tailText
    }
    if (this.tailInCodeBlock !== split.tailInCodeBlock) {
      this.tailInCodeBlock = split.tailInCodeBlock
    }
  }

  /**
   * 重置稳定节点缓存与数据源。
   */
  private resetStableNodes(): void {
    this.stableNodes = []
    this.stableDataSource.clear()
    this.consumedStableLength = 0
    this.stableSegmentSerial = 0
  }

  /**
   * 解析新增稳定 Markdown 片段并追加到稳定节点数据源。
   *
   * @param text - 新增的稳定 Markdown 文本
   */
  private appendStableText(text: string): void {
    if (text.trim().length === 0) {
      return
    }
    const addedNodes: MdNode[] = parseMd(text)
    if (addedNodes.length === 0) {
      return
    }
    this.stableSegmentSerial++
    prefixNodeKeys(addedNodes, 'stream_' + this.stableSegmentSerial.toString())
    this.stableNodes = this.stableNodes.concat(addedNodes)
    this.stableDataSource.appendAll(addedNodes)
  }

  /**
   * 构建流式 Markdown 视图。
   */
  build() {
    Column() {
      if (this.stableNodes.length > 0) {
        MdNodesView({
          nodes: this.stableNodes,
          onLinkClick: this.onLinkClick,
          forceLazy: true,
          dataSource: this.stableDataSource
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
   * 渲染普通尾段文本与静态流式游标。
   */
  @Builder
  RenderTextTail() {
    Text() {
      Span(this.tailText).fontColor(AppColors.textPrimary)
      Span('▌').fontColor(AppColors.primary).fontSize(14)
    }
    .fontSize(15)
    .fontColor(AppColors.textPrimary)
    .lineHeight(26)
    .width('100%')
    .margin({ top: 2, bottom: 6 })
  }

  /**
   * 渲染未闭合代码块尾段与静态流式游标。
   */
  @Builder
  RenderCodeTail() {
    Scroll() {
      Text() {
        Span(this.tailText)
          .fontSize(13)
          .fontColor(AppColors.textPrimary)
        Span('▌').fontColor(AppColors.primary).fontSize(13)
      }
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

/**
 * 为一批增量解析节点添加唯一 key 前缀，避免不同片段之间 key 冲突。
 *
 * @param nodes - 节点列表
 * @param prefix - key 前缀
 */
function prefixNodeKeys(nodes: MdNode[], prefix: string): void {
  for (let i: number = 0; i < nodes.length; i++) {
    prefixNodeKey(nodes[i], prefix)
  }
}

/**
 * 为单个节点及其子节点添加唯一 key 前缀。
 *
 * @param node - Markdown AST 节点
 * @param prefix - key 前缀
 */
function prefixNodeKey(node: MdNode, prefix: string): void {
  if (node.key.length > 0) {
    node.key = prefix + '_' + node.key
  } else {
    node.key = prefix + '_' + node.id.toString()
  }
  for (let i: number = 0; i < node.children.length; i++) {
    prefixNodeKey(node.children[i], prefix)
  }
}
