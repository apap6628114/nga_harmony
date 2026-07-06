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
}
