import { MdNode, MdNodeType } from '../../model/MdNode'
import { AppColors } from '../constants/Constants'
import { MdNodeDataSource } from '../datasource/MdNodeDataSource'

/**
 * Markdown AST 节点渲染组件。
 *
 * 只负责将已解析的 Markdown 节点渲染为 UI，不负责文本解析。
 */
@Component
export struct MdNodesView {
  /** Markdown AST 节点列表。 */
  @Prop @Watch('onNodesChange') nodes: MdNode[] = []
  /** 链接点击回调。 */
  onLinkClick: (href: string) => void = (_href: string) => {}
  /** 是否强制使用 LazyForEach 数据源渲染。 */
  forceLazy: boolean = false
  /** LazyForEach 数据源。外部增量维护时可传入同一个数据源实例。 */
  dataSource: MdNodeDataSource = new MdNodeDataSource()

  /** 渲染用节点缓存。 */
  @State private renderedNodes: MdNode[] = []

  /** 列宽权重缓存 — 用于避免同一 TABLE 节点多次扫描计算。 */
  private weightCacheKey: number = -1
  /** 列宽权重数组。 */
  private weightCache: number[] = []

  /**
   * 节点列表变化时同步普通渲染缓存与内部数据源。
   */
  private onNodesChange(): void {
    this.renderedNodes = this.nodes
    if (!this.forceLazy) {
      this.dataSource.replaceAll(this.renderedNodes)
    }
  }

  /**
   * 组件出现时初始化渲染缓存。
   */
  aboutToAppear(): void {
    this.renderedNodes = this.nodes
    if (!this.forceLazy) {
      this.dataSource.replaceAll(this.renderedNodes)
    }
  }

  /**
   * 构建 Markdown 节点视图。
   */
  build() {
    Column() {
      if (this.forceLazy || this.renderedNodes.length >= 20) {
        LazyForEach(this.dataSource, (node: MdNode) => {
          this.RenderBlock(node)
        }, (node: MdNode) => this.renderKey(node, 'b'))
      } else {
        ForEach(this.renderedNodes, (node: MdNode) => {
          this.RenderBlock(node)
        }, (node: MdNode) => this.renderKey(node, 'b'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 分派单个块级节点到对应的渲染方法。
   *
   * @param node - 块级节点
   */
  @Builder
  RenderBlock(node: MdNode) {
    if (node.type === MdNodeType.HEADING) {
      this.RenderHeading(node)
    } else if (node.type === MdNodeType.PARAGRAPH) {
      this.RenderParagraph(node)
    } else if (node.type === MdNodeType.CODE_BLOCK) {
      this.RenderCodeBlock(node)
    } else if (node.type === MdNodeType.UNORDERED_LIST) {
      this.RenderUnorderedList(node)
    } else if (node.type === MdNodeType.ORDERED_LIST) {
      this.RenderOrderedList(node)
    } else if (node.type === MdNodeType.BLOCKQUOTE) {
      this.RenderBlockquote(node)
    } else if (node.type === MdNodeType.THEMATIC_BREAK) {
      this.RenderThematicBreak()
    } else if (node.type === MdNodeType.TABLE) {
      this.RenderTable(node)
    }
  }

  /** 渲染标题。 */
  @Builder
  RenderHeading(node: MdNode) {
    Text() {
      ForEach(node.children, (child: MdNode) => {
        this.RenderSpanLeaf(child)
      }, (child: MdNode) => this.renderKey(child, 'h'))
    }
    .fontSize(this.headingFontSize(node.level))
    .fontColor(AppColors.textPrimary)
    .fontWeight(this.headingFontWeight(node.level))
    .lineHeight(this.headingLineHeight(node.level))
    .width('100%')
    .margin({ top: node.level <= 2 ? 14 : 10, bottom: 4 })
  }

  /** 渲染段落。 */
  @Builder
  RenderParagraph(node: MdNode) {
    Text() {
      ForEach(node.children, (child: MdNode) => {
        this.RenderSpanLeaf(child)
      }, (child: MdNode) => this.renderKey(child, 'p'))
    }
    .fontSize(15)
    .fontColor(AppColors.textPrimary)
    .lineHeight(26)
    .width('100%')
    .margin({ top: 2, bottom: 6 })
  }

  /** 渲染围栏代码块。 */
  @Builder
  RenderCodeBlock(node: MdNode) {
    Column() {
      if (node.language.length > 0) {
        Text(node.language)
          .fontSize(11)
          .fontColor(AppColors.textTertiary)
          .padding({ left: 12, right: 12, top: 6, bottom: 4 })
      }
      Scroll() {
        Text(node.text)
          .fontSize(13)
          .fontColor(AppColors.textPrimary)
          .fontFamily('monospace')
          .lineHeight(20)
          .padding(12)
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
    }
    .width('100%')
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(8)
    .margin({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 渲染无序列表。 */
  @Builder
  RenderUnorderedList(node: MdNode) {
    Column() {
      ForEach(node.children, (item: MdNode) => {
        Row() {
          Text('•')
            .fontSize(15)
            .fontColor(AppColors.textPrimary)
            .margin({ right: 6 })
          Text() {
            ForEach(item.children, (child: MdNode) => {
              this.RenderSpanLeaf(child)
            }, (child: MdNode) => this.renderKey(child, 'uli'))
          }
          .fontSize(15)
          .fontColor(AppColors.textPrimary)
          .lineHeight(26)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
        .alignItems(VerticalAlign.Top)
      }, (item: MdNode) => this.renderKey(item, 'uli'))
    }
    .width('100%')
    .padding({ left: 8 })
    .margin({ top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 渲染有序列表。 */
  @Builder
  RenderOrderedList(node: MdNode) {
    Column() {
      ForEach(node.children, (item: MdNode, index: number) => {
        Row() {
          Text((index + 1).toString() + '.')
            .fontSize(15)
            .fontColor(AppColors.textPrimary)
            .margin({ right: 6 })
          Text() {
            ForEach(item.children, (child: MdNode) => {
              this.RenderSpanLeaf(child)
            }, (child: MdNode) => this.renderKey(child, 'ol'))
          }
          .fontSize(15)
          .fontColor(AppColors.textPrimary)
          .lineHeight(26)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
        .alignItems(VerticalAlign.Top)
      }, (item: MdNode) => this.renderKey(item, 'ol'))
    }
    .width('100%')
    .padding({ left: 8 })
    .margin({ top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 渲染引用块。 */
  @Builder
  RenderBlockquote(node: MdNode) {
    Column() {
      Text() {
        ForEach(node.children, (child: MdNode) => {
          this.RenderSpanLeaf(child)
        }, (child: MdNode) => this.renderKey(child, 'bq'))
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
  }

  /** 渲染分隔线。 */
  @Builder
  RenderThematicBreak() {
    Divider()
      .color(AppColors.separator)
      .margin({ top: 10, bottom: 10 })
      .width('100%')
  }

  /**
   * 渲染 GFM 表格。
   *
   * 采用 Row/Column + layoutWeight 等宽列布局，
   * 表头行加背景色区分，各列按分隔行指定的对齐方式渲染文本。
   *
   * @param node - TABLE 类型节点，children 为 TABLE_ROW 节点
   */
  @Builder
  RenderTable(node: MdNode) {
    Scroll() {
      Column() {
        ForEach(node.children, (row: MdNode, rowIndex: number) => {
          Row() {
            ForEach(row.children, (cell: MdNode, colIndex: number) => {
              Column() {
                Text() {
                  ForEach(cell.children, (child: MdNode) => {
                    this.RenderSpanLeaf(child)
                  }, (child: MdNode) => this.renderKey(child, 'tci'))
                }
                .width('100%')
                .textAlign(this.toCellTextAlign(cell.align))
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              }
              .padding(8)
              .layoutWeight(this.getColumnWeight(node, colIndex))
              .border({ width: 0.5, color: AppColors.separator })
              .alignItems(HorizontalAlign.Start)
            }, (cell: MdNode, colIndex: number) => this.renderKey(cell, 'tc'))
          }
          .width('100%')
          .backgroundColor(rowIndex === 0 ? AppColors.bgSecondary : Color.Transparent)
        }, (row: MdNode) => this.renderKey(row, 'tr'))
      }
      .width(this.getTableMinWidth(node))
      .border({ width: 0.5, color: AppColors.separator })
      .borderRadius(4)
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
    .margin({ top: 6, bottom: 6 })
  }

  /**
   * 返回 ArkUI ForEach 使用的渲染 key。
   *
   * @param node - Markdown AST 节点
   * @param fallbackPrefix - 无稳定 key 时使用的前缀
   * @returns 渲染 key
   */
  private renderKey(node: MdNode, fallbackPrefix: string): string {
    if (node.key.length > 0) {
      return node.key
    }
    return fallbackPrefix + '_' + node.id.toString()
  }

  /**
   * 渲染段落中的内联叶子节点为 Span。
   *
   * @param node - 内联叶子节点
   */
  @Builder
  RenderSpanLeaf(node: MdNode) {
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
        .onClick(() => {
          if (node.href.length > 0) {
            this.onLinkClick(node.href)
          }
        })
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
   * 根据标题级别返回对应字号。
   *
   * @param level - 标题级别
   * @returns 字号值
   */
  private headingFontSize(level: number): number {
    if (level === 1) {
      return 22
    }
    if (level === 2) {
      return 19
    }
    if (level === 3) {
      return 17
    }
    if (level === 4) {
      return 15
    }
    if (level === 5) {
      return 14
    }
    return 13
  }

  /**
   * 根据标题级别返回对应字重。
   *
   * @param level - 标题级别
   * @returns 字重
   */
  private headingFontWeight(level: number): FontWeight {
    if (level <= 2) {
      return FontWeight.Bold
    }
    return FontWeight.Medium
  }

  /**
   * 根据标题级别返回对应行高。
   *
   * @param level - 标题级别
   * @returns 行高
   */
  private headingLineHeight(level: number): number {
    if (level === 1) {
      return 30
    }
    if (level === 2) {
      return 27
    }
    if (level === 3) {
      return 24
    }
    return 22
  }

  /**
   * 将对齐字符串转为 ArkUI TextAlign 枚举。
   *
   * @param align - 对齐字符串（'left' | 'center' | 'right'）
   * @returns 对应的 TextAlign 值
   */
  private toCellTextAlign(align: string): TextAlign {
    if (align === 'center') {
      return TextAlign.Center
    }
    if (align === 'right') {
      return TextAlign.End
    }
    return TextAlign.Start
  }

  /**
   * 获取表格指定列的布局权重（带缓存）。
   *
   * 首次调用时扫描全表计算权重，后续列复用缓存。
   * 缓存以 TABLE 节点 id 为 key，同一张表只计算一次。
   *
   * @param node - TABLE 类型节点
   * @param colIndex - 列索引
   * @returns 该列的权重值
   */
  private getColumnWeight(node: MdNode, colIndex: number): number {
    if (this.weightCacheKey !== node.id) {
      this.weightCache = this.computeColumnWeights(node)
      this.weightCacheKey = node.id
    }
    return colIndex < this.weightCache.length ? this.weightCache[colIndex] : 1
  }

  /**
   * 基于列权重估算表格总渲染宽度（vp）。
   *
   * 每单位权重 = 90vp，下限 340vp（典型手机屏幕宽度），
   * 确保窄表填满视口、宽表触发水平滚动。
   *
   * @param node - TABLE 类型节点
   * @returns 表格总宽度（vp）
   */
  private getTableMinWidth(node: MdNode): number {
    const rows: MdNode[] = node.children
    if (rows.length === 0) {
      return 340
    }
    const colCount: number = rows[0].children.length
    let totalWeight: number = 0
    for (let c: number = 0; c < colCount; c++) {
      totalWeight += this.getColumnWeight(node, c)
    }
    const pxWidth: number = totalWeight * 90
    // 不低于 340vp，让窄表也基本填满屏幕
    return pxWidth > 340 ? pxWidth : 340
  }

  /**
   * 递归提取内联 AST 子树的纯文本，用于估算渲染宽度。
   *
   * 仅处理内联节点类型（TEXT / BOLD / ITALIC / STRIKETHROUGH /
   * CODE_INLINE / LINK），遇到块级节点则返回空串。
   *
   * @param node - 内联 AST 节点
   * @returns 拼接后的纯文本
   */
  private flattenCellText(node: MdNode): string {
    if (node.type === MdNodeType.TEXT || node.type === MdNodeType.CODE_INLINE ||
      node.type === MdNodeType.LINK) {
      return node.text
    }
    if (node.type === MdNodeType.BOLD || node.type === MdNodeType.ITALIC ||
      node.type === MdNodeType.STRIKETHROUGH) {
      // compressSingleTextChild 优化后的叶子
      if (node.children.length === 0) {
        return node.text
      }
    }
    // 递归子节点
    let result: string = ''
    for (let i: number = 0; i < node.children.length; i++) {
      result += this.flattenCellText(node.children[i])
    }
    return result
  }

  /**
   * 基于表格内容计算各列的布局权重。
   *
   * 扫描所有行的所有单元格，统计每列最长纯文本长度，
   * 线性映射到 [1, 3] 权重区间。等长列退化为等宽。
   *
   * @param node - TABLE 类型节点
   * @returns 各列权重数组
   */
  private computeColumnWeights(node: MdNode): number[] {
    const rows: MdNode[] = node.children
    if (rows.length === 0) {
      return [1]
    }
    const colCount: number = rows[0].children.length
    if (colCount <= 1) {
      return [1]
    }

    // 统计每列最大文本长度
    const maxChars: number[] = new Array<number>(colCount).fill(0)
    for (let r: number = 0; r < rows.length; r++) {
      const cells: MdNode[] = rows[r].children
      for (let c: number = 0; c < cells.length && c < colCount; c++) {
        const textLen: number = this.flattenCellText(cells[c]).length
        if (textLen > maxChars[c]) {
          maxChars[c] = textLen
        }
      }
    }

    // 找到最小和最大值
    let minChars: number = maxChars[0]
    let maxCharsVal: number = maxChars[0]
    for (let c: number = 1; c < colCount; c++) {
      if (maxChars[c] < minChars) {
        minChars = maxChars[c]
      }
      if (maxChars[c] > maxCharsVal) {
        maxCharsVal = maxChars[c]
      }
    }

    // 避免除零，等长时退化为等宽
    if (minChars < 1) {
      minChars = 1
    }
    const range: number = maxCharsVal - minChars
    if (range <= 0) {
      return new Array<number>(colCount).fill(1)
    }

    // 线性映射到 [1, 3]
    const weights: number[] = []
    for (let c: number = 0; c < colCount; c++) {
      weights.push(1 + ((maxChars[c] - minChars) / range) * 2)
    }
    return weights
  }
}
