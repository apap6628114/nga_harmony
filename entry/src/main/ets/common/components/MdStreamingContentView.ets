import { MdNode, MdNodeType } from '../../model/MdNode'
import { parseMd } from '../../parser/md/MdParser'
import { MdNodeDataSource } from '../datasource/MdNodeDataSource'
import { AppColors } from '../constants/Constants'
import { MdNodesView } from './MdNodesView'

/**
 * 流式 Markdown 拆分结果。
 *
 * 采用"逐行稳定"策略：非代码块内的每个完整行（以 \n 结尾）都视作稳定块，
 * 立即送入 AST 解析渲染。尾段仅包含当前未完结行和未闭合代码块内的内容。
 * 这种策略让标量、段落、列表项等在流式过程中即时获得 Markdown 格式化，
 * 显著提升感知流畅度。最终气泡由 MdContentView 完整解析纠正。
 */
class MarkdownStreamSplit {
  /** 已到达"逐行稳定"边界的 Markdown 前缀，可安全送入 AST 解析渲染。 */
  stableText: string = ''
  /** 仍在增长中的尾部文本（当前行未完结，或位于未闭合代码块内）。 */
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
  private stableNodes: MdNode[] = []
  /** 当前是否已有稳定 Markdown 节点。 */
  @State private hasStableNodes: boolean = false
  /** 正在增长的尾部文本。 */
  @State private tailText: string = ''
  /** 尾部文本的内联解析节点（贪婪格式化：未闭合标记也渲染）。 */
  @State private tailInlineNodes: MdNode[] = []
  /** 尾段块级前缀类型（''/ 'heading' / 'blockquote' / 'ul' / 'ol'）。 */
  @State private tailBlockPrefix: string = ''
  /** 尾段块级前缀层级（heading: 1-6, ol: 起始序号, 其他: 0）。 */
  @State private tailBlockLevel: number = 0
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
      if (!this.tailInCodeBlock) {
        const blockInfo: TailBlockInfo = splitTailBlockPrefix(split.tailText)
        this.tailBlockPrefix = blockInfo.blockType
        this.tailBlockLevel = blockInfo.blockLevel
        this.tailInlineNodes = parseTailInline(blockInfo.content)
      }
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
    this.hasStableNodes = false
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
    for (let i: number = 0; i < addedNodes.length; i++) {
      this.stableNodes.push(addedNodes[i])
    }
    this.stableDataSource.appendAll(addedNodes)
    if (!this.hasStableNodes) {
      this.hasStableNodes = true
    }
  }

  /**
   * 构建流式 Markdown 视图。
   */
  build() {
    Column() {
      if (this.hasStableNodes) {
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
   *
   * 尾段文本通过贪婪内联解析器格式化。同时检测块级前缀（#、>、-、1.）
   * 即时应用对应层级样式（标题字号、引用左边框、列表项目符号等），
   * 利用 Markdown "层级信息由左侧前缀唯一确定" 的特性。
   */
  @Builder
  RenderTextTail() {
    if (this.tailBlockPrefix === 'heading') {
      // 标题 — 前缀可见即确定层级
      Text() {
        ForEach(this.tailInlineNodes, (node: MdNode) => {
          this.RenderTailSpan(node)
        }, (node: MdNode) => 't_' + node.id.toString())
        Span('▌').fontColor(AppColors.primary).fontSize(14)
      }
      .fontSize(this.tailHeadingFontSize(this.tailBlockLevel))
      .fontColor(AppColors.textPrimary)
      .fontWeight(this.tailBlockLevel <= 2 ? FontWeight.Bold : FontWeight.Medium)
      .lineHeight(this.tailBlockLevel <= 2 ? 30 : 26)
      .width('100%')
      .margin({ top: this.tailBlockLevel <= 2 ? 14 : 10, bottom: 4 })
    } else if (this.tailBlockPrefix === 'blockquote') {
      // 引用 — 前缀可见即确定块级样式
      Column() {
        Text() {
          ForEach(this.tailInlineNodes, (node: MdNode) => {
            this.RenderTailSpan(node)
          }, (node: MdNode) => 't_' + node.id.toString())
          Span('▌').fontColor(AppColors.primary).fontSize(13)
        }
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .fontStyle(FontStyle.Italic)
        .lineHeight(24)
        .width('100%')
      }
      .width('100%')
      .padding({ left: 12, top: 6, bottom: 6 })
      .margin({ top: 6, bottom: 4 })
      .border({
        width: { left: 2 },
        color: { left: AppColors.quoteBorders[0] },
        style: { left: BorderStyle.Solid }
      })
      .borderRadius({ topLeft: 4, bottomLeft: 4 })
      .alignItems(HorizontalAlign.Start)
    } else if (this.tailBlockPrefix === 'ul') {
      // 无序列表 — 显示项目符号
      Row() {
        Text('•')
          .fontSize(15)
          .fontColor(AppColors.textPrimary)
          .margin({ right: 6 })
        Text() {
          ForEach(this.tailInlineNodes, (node: MdNode) => {
            this.RenderTailSpan(node)
          }, (node: MdNode) => 't_' + node.id.toString())
          Span('▌').fontColor(AppColors.primary).fontSize(14)
        }
        .fontSize(15)
        .fontColor(AppColors.textPrimary)
        .lineHeight(26)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
      .margin({ top: 4, bottom: 4 })
      .alignItems(VerticalAlign.Top)
    } else if (this.tailBlockPrefix === 'ol') {
      // 有序列表 — 显示序号
      Row() {
        Text(this.tailBlockLevel.toString() + '.')
          .fontSize(15)
          .fontColor(AppColors.textPrimary)
          .margin({ right: 6 })
        Text() {
          ForEach(this.tailInlineNodes, (node: MdNode) => {
            this.RenderTailSpan(node)
          }, (node: MdNode) => 't_' + node.id.toString())
          Span('▌').fontColor(AppColors.primary).fontSize(14)
        }
        .fontSize(15)
        .fontColor(AppColors.textPrimary)
        .lineHeight(26)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
      .margin({ top: 4, bottom: 4 })
      .alignItems(VerticalAlign.Top)
    } else if (this.tailBlockPrefix === 'table') {
      // 表格行 — 按 | 拆分单元格
      Row() {
        ForEach(this.parseTailTableCells(this.tailText), (cellText: string, cellIndex: number) => {
          Column() {
            Text(cellText)
              .fontSize(13)
              .fontColor(AppColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding(6)
          .layoutWeight(1)
          .border({ width: 0.5, color: AppColors.separator })
        }, (cellText: string, cellIndex: number) => 'ttc_' + cellIndex.toString())
        Text() {
          Span('▌').fontColor(AppColors.primary).fontSize(13)
        }
      }
      .width('100%')
      .margin({ top: 4, bottom: 4 })
    } else {
      // 普通段落 — 纯内联格式化
      Text() {
        ForEach(this.tailInlineNodes, (node: MdNode) => {
          this.RenderTailSpan(node)
        }, (node: MdNode) => 't_' + node.id.toString())
        Span('▌').fontColor(AppColors.primary).fontSize(14)
      }
      .fontSize(15)
      .fontColor(AppColors.textPrimary)
      .lineHeight(26)
      .width('100%')
      .margin({ top: 2, bottom: 6 })
    }
  }

  /**
   * 根据标题级别返回对应字号。
   *
   * @param level - 标题级别 1-6
   * @returns 字号值
   */
  private tailHeadingFontSize(level: number): number {
    if (level === 1) { return 22 }
    if (level === 2) { return 19 }
    if (level === 3) { return 17 }
    if (level === 4) { return 15 }
    if (level === 5) { return 14 }
    return 13
  }

  /**
   * 将尾段表格行文本按 `|` 拆分为单元格数组。
   *
   * @param text - 表格行原始文本（含首尾可选 |）
   * @returns 去除首尾空白后的单元格文本数组
   */
  private parseTailTableCells(text: string): string[] {
    let trimmed: string = text.trim()
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1)
    }
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1)
    }
    const parts: string[] = trimmed.split('|')
    const cells: string[] = []
    for (let i: number = 0; i < parts.length; i++) {
      const cell: string = parts[i].trim()
      if (cell.length > 0) {
        cells.push(cell)
      }
    }
    return cells
  }

  /**
   * 渲染尾段文本中单个内联节点的格式化 Span。
   *
   * @param node - 内联节点（TEXT / BOLD / ITALIC / CODE_INLINE / STRIKETHROUGH / LINK）
   */
  @Builder
  RenderTailSpan(node: MdNode) {
    if (node.type === MdNodeType.CODE_INLINE) {
      Span(node.text)
        .fontFamily('monospace')
        .fontSize(13)
        .fontColor(AppColors.warnText)
        .textBackgroundStyle({ color: AppColors.bgSecondary })
    } else if (node.type === MdNodeType.LINK) {
      Span(node.text)
        .fontColor(AppColors.primary)
        .decoration({ type: TextDecorationType.Underline, color: AppColors.primary })
    } else if (node.type === MdNodeType.BOLD) {
      Span(node.text).fontWeight(FontWeight.Bold).fontColor(AppColors.textPrimary)
    } else if (node.type === MdNodeType.ITALIC) {
      Span(node.text).fontStyle(FontStyle.Italic).fontColor(AppColors.textPrimary)
    } else if (node.type === MdNodeType.STRIKETHROUGH) {
      Span(node.text).decoration({ type: TextDecorationType.LineThrough }).fontColor(AppColors.textPrimary)
    } else {
      Span(node.text).fontColor(AppColors.textPrimary)
    }
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
        Span('▌').fontColor(AppColors.textTertiary).fontSize(13)
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
 * 稳定边界策略（逐行提交）：
 * - 非代码块区域：**每行**（以 \n 结尾的完整行）都是稳定边界。
 *   标题、段落、列表项、分隔线等到达即提交 AST，无需等待空行。
 *   不会截断 mid-line，因为仅当行完整（遇到 \n）时才推进边界。
 * - 代码块区域：围栏闭合前不推进稳定边界，整块以 tail 滞留，
 *   避免不完整的代码块内容进入 AST。
 *
 * 设计权衡：流式期间相同段落的多行会被拆成多个独立段落节点，
 * 流式结束后 MdContentView 会做完整正确解析，这是临时可接受的。
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
    if (!inCodeBlock && i < normalized.length) {
      // 每个以换行符结尾的完整行都标记为稳定边界。
      // 相比"仅空行"策略，此方案让标题、段落、列表项等立即进入 AST 格式化渲染，
      // 而非滞留 tail 区以纯文本展示。流式结束后 MdContentView 会做完整正确解析，
      // 流式期间的段落分割差异（同一段多行变成多段）是临时可接受的视觉表现。
      stableBoundary = i + 1
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

// ============================================================
// 尾段贪婪内联解析
// ============================================================

/**
 * 尾段文本的块级前缀检测结果。
 */
class TailBlockInfo {
  /** 去除块前缀后的正文文本，用于内联解析。 */
  content: string = ''
  /** 块类型：'heading' / 'blockquote' / 'ul' / 'ol' / ''。 */
  blockType: string = ''
  /** 块层级（heading: 1-6, ol: 起始序号, 其他: 0）。 */
  blockLevel: number = 0
}

/**
 * 检测尾段文本的块级前缀并提取正文。
 *
 * 层级信息（# 数量、> 深度、缩进）由左侧前缀唯一确定，
 * 无需等待行尾即可应用对应样式。
 *
 * @param text - 原始尾段文本
 * @returns 检测结果（块类型 + 去前缀正文）
 */
function splitTailBlockPrefix(text: string): TailBlockInfo {
  const result: TailBlockInfo = new TailBlockInfo()

  // ATX 标题：^#{1,6}(\s|$)
  const hMatch: RegExpExecArray | null = /^(#{1,6})(?:\s+|$)/.exec(text)
  if (hMatch !== null) {
    result.blockType = 'heading'
    result.blockLevel = hMatch[1].length
    result.content = text.substring(hMatch[0].length)
    return result
  }

  // 引用块：^> 或 ^>
  if (text.startsWith('> ')) {
    result.blockType = 'blockquote'
    result.blockLevel = 1
    result.content = text.substring(2)
    return result
  }
  if (text.startsWith('>')) {
    result.blockType = 'blockquote'
    result.blockLevel = 1
    result.content = text.substring(1)
    return result
  }

  // 无序列表：^\s*[-*+]\s+
  const ulMatch: RegExpExecArray | null = /^(\s*)[-*+]\s+(.+)$/.exec(text)
  if (ulMatch !== null) {
    result.blockType = 'ul'
    result.blockLevel = ulMatch[1].length
    result.content = ulMatch[2]
    return result
  }
  // 仅有无序列表标记但无内容
  if (/^(\s*)[-*+]\s*$/.exec(text) !== null) {
    result.blockType = 'ul'
    result.content = ''
    return result
  }

  // 有序列表：^\s*\d+\.\s+
  const olMatch: RegExpExecArray | null = /^(\s*)(\d+)\.\s+(.+)$/.exec(text)
  if (olMatch !== null) {
    result.blockType = 'ol'
    result.blockLevel = parseInt(olMatch[2])
    result.content = olMatch[3]
    return result
  }
  if (/^(\s*)(\d+)\.\s*$/.exec(text) !== null) {
    result.blockType = 'ol'
    result.content = ''
    return result
  }

  // 表格行：| 前缀
  if (text.startsWith('|')) {
    result.blockType = 'table'
    result.content = text
    return result
  }

  // 纯段落
  result.content = text
  return result
}

/**
 * 贪婪解析尾段文本中的内联格式标记。
 *
 * 与标准 parseInline 的关键区别：当行内标记（**、*、`、~~）未闭合时，
 * 从标记位置到文本末尾仍按格式化渲染，而非回退为纯文本。
 * 链接 [text](url) 仅在完整时才渲染为链接。
 *
 * 此策略利用 Markdown "只需前缀数据即可开始格式化" 的特性，
 * 在流式输出的尾段中获得更及时的视觉反馈。
 * 流式结束后完整文本会由 MdContentView 做标准解析，无需担忧误渲染。
 *
 * @param text - 尾段原始文本
 * @returns 贪婪解析后的内联节点列表
 */
function parseTailInline(text: string): MdNode[] {
  const result: MdNode[] = []
  const len: number = text.length
  if (len === 0) {
    return result
  }

  let pos: number = 0
  let textStart: number = 0

  while (pos < len) {
    const ch: string = text.charAt(pos)

    // 转义 \*
    if (ch === '\\' && pos + 1 < len) {
      tailFlushText(text, textStart, pos, result)
      const escapedNode: MdNode = new MdNode(MdNodeType.TEXT)
      escapedNode.text = text.charAt(pos + 1)
      result.push(escapedNode)
      pos += 2
      textStart = pos
      continue
    }

    // 行内代码 `code` — 未闭合时贪婪匹配到末尾
    if (ch === '`') {
      const end: number = text.indexOf('`', pos + 1)
      tailFlushText(text, textStart, pos, result)
      const codeNode: MdNode = new MdNode(MdNodeType.CODE_INLINE)
      codeNode.text = end >= 0 ? text.substring(pos + 1, end) : text.substring(pos + 1)
      result.push(codeNode)
      pos = end >= 0 ? end + 1 : len
      textStart = pos
      continue
    }

    // 粗体 **text** — 未闭合时贪婪匹配到末尾
    if (ch === '*' && pos + 1 < len && text.charAt(pos + 1) === '*') {
      const end: number = text.indexOf('**', pos + 2)
      tailFlushText(text, textStart, pos, result)
      const boldNode: MdNode = new MdNode(MdNodeType.BOLD)
      boldNode.text = end >= 0 ? text.substring(pos + 2, end) : text.substring(pos + 2)
      result.push(boldNode)
      pos = end >= 0 ? end + 2 : len
      textStart = pos
      continue
    }

    // 斜体 *text* — 未闭合时贪婪匹配到末尾
    if (ch === '*') {
      const end: number = tailFindSingleCharMarker(text, '*', pos + 1, len)
      tailFlushText(text, textStart, pos, result)
      const italicNode: MdNode = new MdNode(MdNodeType.ITALIC)
      italicNode.text = end >= 0 ? text.substring(pos + 1, end) : text.substring(pos + 1)
      result.push(italicNode)
      pos = end >= 0 ? end + 1 : len
      textStart = pos
      continue
    }

    // 删除线 ~~text~~ — 未闭合时贪婪匹配到末尾
    if (ch === '~' && pos + 1 < len && text.charAt(pos + 1) === '~') {
      const end: number = text.indexOf('~~', pos + 2)
      tailFlushText(text, textStart, pos, result)
      const strikeNode: MdNode = new MdNode(MdNodeType.STRIKETHROUGH)
      strikeNode.text = end >= 0 ? text.substring(pos + 2, end) : text.substring(pos + 2)
      result.push(strikeNode)
      pos = end >= 0 ? end + 2 : len
      textStart = pos
      continue
    }

    // 链接 [text](url) — 仅在完整时渲染，不完整时跳过 [ 作为普通文本
    if (ch === '[') {
      const closeBracket: number = text.indexOf(']', pos + 1)
      if (closeBracket >= 0 && closeBracket + 1 < len && text.charAt(closeBracket + 1) === '(') {
        const closeParen: number = text.indexOf(')', closeBracket + 2)
        if (closeParen >= 0) {
          tailFlushText(text, textStart, pos, result)
          const linkNode: MdNode = new MdNode(MdNodeType.LINK)
          linkNode.text = text.substring(pos + 1, closeBracket)
          linkNode.href = text.substring(closeBracket + 2, closeParen)
          result.push(linkNode)
          pos = closeParen + 1
          textStart = pos
          continue
        }
      }
      // 不完整的链接，[ 作为普通文本
      pos++
      continue
    }

    pos++
  }

  // 刷新尾部纯文本
  tailFlushText(text, textStart, len, result)
  return result
}

/**
 * 将 text[start..end) 段作为 TEXT 节点追加到 result。
 *
 * @param text - 源文本
 * @param start - 段起始位置
 * @param end - 段结束位置（不含）
 * @param result - 目标节点数组
 */
function tailFlushText(text: string, start: number, end: number, result: MdNode[]): void {
  if (end > start) {
    const textNode: MdNode = new MdNode(MdNodeType.TEXT)
    textNode.text = text.substring(start, end)
    result.push(textNode)
  }
}

/**
 * 查找尾段文本中的单字符标记（*）的闭合位置。
 *
 * 跳过连续双字符标记（**），避免误匹配。
 *
 * @param text - 源文本
 * @param marker - 标记字符
 * @param from - 搜索起始位置
 * @param len - 文本长度
 * @returns 闭合位置，-1 表示未找到
 */
function tailFindSingleCharMarker(text: string, marker: string, from: number, len: number): number {
  let i: number = from
  while (i < len) {
    if (text.charAt(i) === marker) {
      if (i + 1 < len && text.charAt(i + 1) === marker) {
        i += 2
        continue
      }
      return i
    }
    i++
  }
  return -1
}
