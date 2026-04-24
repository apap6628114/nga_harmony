import { BBNode, BBNodeType } from '../model/BBCodeNode'
import { AppColors } from '../common/Constants'
import { getEmotionResource } from '../common/EmotionResources'

function isInlineNode(type: BBNodeType): boolean {
  return type === BBNodeType.TEXT || type === BBNodeType.BOLD ||
    type === BBNodeType.ITALIC || type === BBNodeType.UNDERLINE ||
    type === BBNodeType.STRIKETHROUGH || type === BBNodeType.COLOR ||
    type === BBNodeType.SIZE || type === BBNodeType.FONT ||
    type === BBNodeType.URL || type === BBNodeType.PID_LINK ||
    type === BBNodeType.UID_LINK || type === BBNodeType.TID_LINK ||
    type === BBNodeType.MENTION || type === BBNodeType.EMOTION
}

const QUOTE_BORDER_COLORS: string[] = [
  'rgba(0, 122, 255, 0.3)',
  'rgba(0, 122, 255, 0.2)',
  'rgba(0, 122, 255, 0.12)',
]

class RenderContext {
  inQuote: boolean = false
  quoteDepth: number = 0
}

@Component
export struct BBCodeContentView {
  nodes: BBNode[] = []
  @State collapseKeys: Set<string> = new Set()
  onImageClick: (urls: string[], index: number) => void = (_urls: string[], _index: number) => {}
  onLinkClick: (href: string) => void = (_href: string) => {}

  private getImageUrls(): string[] {
    return this.collectUrls(this.nodes)
  }

  private collectUrls(nodes: BBNode[]): string[] {
    const urls: string[] = []
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i]
      if (n.type === BBNodeType.IMAGE && n.src.length > 0) {
        urls.push(n.src)
      }
      if (n.children.length > 0) {
        const childUrls = this.collectUrls(n.children)
        for (let j = 0; j < childUrls.length; j++) {
          urls.push(childUrls[j])
        }
      }
    }
    return urls
  }

  build() {
    Column() {
      if (this.nodes.length > 0) {
        this.RenderChildren(this.nodes, new RenderContext())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private splitIntoGroups(nodes: BBNode[]): NodeGroup[] {
    const groups: NodeGroup[] = []
    let i = 0
    while (i < nodes.length) {
      if (isInlineNode(nodes[i].type)) {
        const inlineNodes: BBNode[] = []
        while (i < nodes.length && isInlineNode(nodes[i].type)) {
          inlineNodes.push(nodes[i])
          i++
        }
        const g = new NodeGroup()
        g.kind = 'inline'
        g.nodes = inlineNodes
        groups.push(g)
      } else {
        const g = new NodeGroup()
        g.kind = 'block'
        g.nodes = [nodes[i]]
        groups.push(g)
        i++
      }
    }
    return groups
  }

  @Builder
  RenderChildren(nodes: BBNode[], ctx: RenderContext) {
    ForEach(this.splitIntoGroups(nodes), (group: NodeGroup) => {
      if (group.kind === 'inline') {
        Text() {
          ForEach(group.nodes, (node: BBNode) => {
            this.RenderInlineSpan(node, ctx)
          })
        }
        .fontSize(ctx.inQuote ? 14 : 15)
        .fontColor(ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary)
        .fontStyle(ctx.inQuote ? FontStyle.Italic : FontStyle.Normal)
        .lineHeight(ctx.inQuote ? 20 : 22)
        .width('100%')
      } else {
        this.RenderBlockNode(group.nodes[0], ctx)
      }
    })
  }

  @Builder
  RenderInlineSpan(node: BBNode, ctx: RenderContext) {
    if (node.type === BBNodeType.TEXT) {
      Span(node.text)
        .fontColor(ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary)
    } else if (node.type === BBNodeType.BOLD) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Bold, FontStyle.Normal, TextDecorationType.None, '', 0, '')
    } else if (node.type === BBNodeType.ITALIC) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Normal, FontStyle.Italic, TextDecorationType.None, '', 0, '')
    } else if (node.type === BBNodeType.UNDERLINE) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Normal, FontStyle.Normal, TextDecorationType.Underline, '', 0, '')
    } else if (node.type === BBNodeType.STRIKETHROUGH) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Normal, FontStyle.Normal, TextDecorationType.LineThrough, '', 0, '')
    } else if (node.type === BBNodeType.COLOR) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Normal, FontStyle.Normal, TextDecorationType.None, node.color, 0, '')
    } else if (node.type === BBNodeType.SIZE) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Normal, FontStyle.Normal, TextDecorationType.None, '', node.size, '')
    } else if (node.type === BBNodeType.FONT) {
      this.RenderFormattedSpan(node, ctx, FontWeight.Normal, FontStyle.Normal, TextDecorationType.None, '', 0, node.fontFamily)
    } else if (node.type === BBNodeType.URL || node.type === BBNodeType.PID_LINK ||
      node.type === BBNodeType.UID_LINK || node.type === BBNodeType.TID_LINK ||
      node.type === BBNodeType.MENTION) {
      Span(node.text)
        .fontColor(AppColors.primary)
        .decoration({ type: TextDecorationType.Underline, color: AppColors.primary })
        .onClick(() => {
          if (node.href.length > 0) {
            this.onLinkClick(node.href)
          }
        })
    } else if (node.type === BBNodeType.EMOTION) {
      if (getEmotionResource(node.emotionCat, node.emotionCode) !== null) {
        ImageSpan(getEmotionResource(node.emotionCat, node.emotionCode))
          .width(ctx.inQuote ? 20 : 24)
          .height(ctx.inQuote ? 20 : 24)
          .objectFit(ImageFit.Contain)
      } else {
        Span(`[表情:${node.emotionCat}:${node.emotionCode}]`)
          .fontSize(ctx.inQuote ? 12 : 14)
          .fontColor(AppColors.textTertiary)
      }
    }
  }

  @Builder
  RenderFormattedSpan(node: BBNode, ctx: RenderContext,
    weight: FontWeight, style: FontStyle, deco: TextDecorationType,
    color: string, size: number, family: string) {
    if (node.children.length > 0) {
      ForEach(node.children, (child: BBNode) => {
        this.RenderSpanWithFormat(child, ctx, weight, style, deco, color, size, family)
      })
    } else {
      Span(node.text)
        .fontWeight(weight)
        .fontStyle(style)
        .fontColor(color.length > 0 ? color : (ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary))
        .fontSize(size > 0 ? size : (ctx.inQuote ? 14 : 15))
    }
  }

  @Builder
  RenderSpanWithFormat(child: BBNode, ctx: RenderContext,
    weight: FontWeight, style: FontStyle, deco: TextDecorationType,
    color: string, size: number, family: string) {
    if (child.type === BBNodeType.URL || child.type === BBNodeType.PID_LINK ||
      child.type === BBNodeType.UID_LINK || child.type === BBNodeType.TID_LINK ||
      child.type === BBNodeType.MENTION) {
      Span(child.text)
        .fontWeight(weight)
        .fontStyle(style)
        .fontColor(AppColors.primary)
        .decoration({ type: TextDecorationType.Underline, color: AppColors.primary })
        .fontSize(size > 0 ? size : (ctx.inQuote ? 14 : 15))
        .onClick(() => {
          if (child.href.length > 0) {
            this.onLinkClick(child.href)
          }
        })
    } else if (child.type === BBNodeType.EMOTION) {
      if (getEmotionResource(child.emotionCat, child.emotionCode) !== null) {
        ImageSpan(getEmotionResource(child.emotionCat, child.emotionCode))
          .width(ctx.inQuote ? 20 : 24)
          .height(ctx.inQuote ? 20 : 24)
          .objectFit(ImageFit.Contain)
      } else {
        Span(`[表情:${child.emotionCat}:${child.emotionCode}]`)
          .fontSize(ctx.inQuote ? 12 : 14)
          .fontColor(AppColors.textTertiary)
      }
    } else if (child.type === BBNodeType.BOLD) {
      Span(child.text)
        .fontWeight(FontWeight.Bold)
        .fontStyle(style)
        .fontColor(color.length > 0 ? color : (ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary))
        .fontSize(size > 0 ? size : (ctx.inQuote ? 14 : 15))
    } else {
      Span(child.text)
        .fontWeight(weight)
        .fontStyle(style)
        .fontColor(color.length > 0 ? color : (ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary))
        .fontSize(size > 0 ? size : (ctx.inQuote ? 14 : 15))
    }
  }

  @Builder
  RenderBlockNode(node: BBNode, ctx: RenderContext) {
    if (node.type === BBNodeType.IMAGE) {
      this.RenderImage(node, ctx)
    } else if (node.type === BBNodeType.QUOTE) {
      this.RenderQuote(node, ctx)
    } else if (node.type === BBNodeType.COLLAPSE) {
      this.RenderCollapse(node, ctx)
    } else if (node.type === BBNodeType.CODE) {
      this.RenderCode(node, ctx)
    } else if (node.type === BBNodeType.LIST) {
      this.RenderList(node, ctx)
    } else if (node.type === BBNodeType.VIDEO) {
      Text('🎬 视频').fontSize(15).fontColor(AppColors.primary).margin({ top: 6, bottom: 4 })
    } else if (node.type === BBNodeType.AUDIO) {
      Text('🎵 音频').fontSize(15).fontColor(AppColors.primary).margin({ top: 6, bottom: 4 })
    } else if (node.type === BBNodeType.DICE) {
      Text('🎲 骰子').fontSize(15).fontColor(AppColors.textPrimary)
    } else if (node.type === BBNodeType.WARN) {
      this.RenderWarn(node, ctx)
    } else if (node.type === BBNodeType.ALBUM) {
      this.RenderAlbum(node, ctx)
    } else if (node.type === BBNodeType.FLOAT_LEFT) {
      this.RenderFloat(node, FlexAlign.Start, ctx)
    } else if (node.type === BBNodeType.FLOAT_RIGHT) {
      this.RenderFloat(node, FlexAlign.End, ctx)
    } else if (node.type === BBNodeType.ALIGN) {
      this.RenderAlign(node, ctx)
    } else if (node.type === BBNodeType.TABLE) {
      this.RenderTable(node, ctx)
    } else if (node.type === BBNodeType.STYLE_DIV) {
      this.RenderStyleDiv(node, ctx)
    } else if (node.type === BBNodeType.POST_BY) {
      this.RenderReplyRef(node, ctx)
    }
  }

  @Builder
  RenderImage(node: BBNode, ctx: RenderContext) {
    if (node.src.length > 0) {
      if (ctx.inQuote) {
        Image(node.src)
          .width('100%')
          .constraintSize({ maxWidth: '100%', maxHeight: 200 })
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .backgroundColor(AppColors.bgSecondary)
          .margin({ top: 6, bottom: 4 })
          .onError(() => {})
          .onClick(() => {
            const allUrls = this.getImageUrls()
            if (allUrls.length > 0) {
              let clickIdx = 0
              for (let i = 0; i < allUrls.length; i++) {
                if (allUrls[i] === node.src) {
                  clickIdx = i
                  break
                }
              }
              this.onImageClick(allUrls, clickIdx)
            } else {
              this.onImageClick([node.src], 0)
            }
          })
      } else {
        Image(node.src)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .backgroundColor(AppColors.bgSecondary)
          .margin({ top: 6, bottom: 4 })
          .onError(() => {})
          .onClick(() => {
            const allUrls = this.getImageUrls()
            if (allUrls.length > 0) {
              let clickIdx = 0
              for (let i = 0; i < allUrls.length; i++) {
                if (allUrls[i] === node.src) {
                  clickIdx = i
                  break
                }
              }
              this.onImageClick(allUrls, clickIdx)
            } else {
              this.onImageClick([node.src], 0)
            }
          })
      }
    }
  }

  @Builder
  RenderQuote(node: BBNode, ctx: RenderContext) {
    Column() {
      this.RenderChildren(node.children, this.makeQuoteCtx(ctx))
    }
    .width('100%')
    .padding({ left: 12, top: 6, bottom: 6 })
    .margin({ top: 6, bottom: 4 })
    .border({
      width: { left: 2 },
      color: { left: QUOTE_BORDER_COLORS[Math.min(ctx.quoteDepth, QUOTE_BORDER_COLORS.length - 1)] },
      style: { left: BorderStyle.Solid }
    })
    .borderRadius({ topLeft: 4, bottomLeft: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  private makeQuoteCtx(parent: RenderContext): RenderContext {
    const c = new RenderContext()
    c.inQuote = true
    c.quoteDepth = parent.quoteDepth + 1
    return c
  }

  @Builder
  RenderReplyRef(node: BBNode, ctx: RenderContext) {
    Column() {
      this.RenderChildren(node.children, this.makeQuoteCtx(ctx))
    }
    .width('100%')
    .padding({ left: 12, top: 6, bottom: 6 })
    .margin({ top: 6, bottom: 4 })
    .border({
      width: { left: 2 },
      color: { left: 'rgba(0, 122, 255, 0.2)' },
      style: { left: BorderStyle.Solid }
    })
    .borderRadius({ topLeft: 4, bottomLeft: 4 })
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxHeight: 80 })
    .opacity(0.85)
  }

  @Builder
  RenderCollapse(node: BBNode, ctx: RenderContext) {
    Column() {
      Row() {
        Text('▸ ' + node.title)
          .fontSize(14)
          .fontColor(AppColors.textSecondary)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      .onClick(() => {
        const s = new Set(this.collapseKeys)
        if (s.has(node.title)) {
          s.delete(node.title)
        } else {
          s.add(node.title)
        }
        this.collapseKeys = s
      })

      if (this.collapseKeys.has(node.title)) {
        Column() {
          this.RenderChildren(node.children, ctx)
        }
        .width('100%')
        .padding({ top: 4 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RenderCode(node: BBNode, ctx: RenderContext) {
    Scroll() {
      Text(node.text)
        .fontSize(13)
        .fontColor(AppColors.textPrimary)
        .fontFamily('monospace')
        .lineHeight(20)
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .padding(10)
    .margin({ top: 6, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(AppColors.bgSecondary)
    .align(Alignment.TopStart)
  }

  @Builder
  RenderList(node: BBNode, ctx: RenderContext) {
    Column() {
      ForEach(node.children, (child: BBNode) => {
        if (child.type === BBNodeType.LIST_ITEM) {
          Row() {
            Text('• ')
              .fontSize(ctx.inQuote ? 14 : 15)
              .fontColor(ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary)
            if (child.children.length > 0) {
              Column() {
                this.RenderChildren(child.children, ctx)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            } else {
              Text(child.text)
                .fontSize(ctx.inQuote ? 14 : 15)
                .fontColor(ctx.inQuote ? AppColors.textSecondary : AppColors.textPrimary)
                .layoutWeight(1)
                .lineHeight(ctx.inQuote ? 20 : 22)
            }
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
          .alignItems(VerticalAlign.Top)
        }
      })
    }
    .width('100%')
    .padding({ left: 12 })
    .margin({ top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RenderWarn(node: BBNode, ctx: RenderContext) {
    Column() {
      if (node.children.length > 0) {
        this.RenderChildren(node.children, ctx)
      } else {
        Text(node.text)
          .fontSize(15)
          .fontColor('#8B0000')
          .lineHeight(22)
      }
    }
    .width('100%')
    .padding(12)
    .margin({ top: 6, bottom: 4 })
    .borderRadius(8)
    .backgroundColor('#FFF3E0')
    .border({ width: 1, color: '#FFB74D' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RenderAlbum(node: BBNode, ctx: RenderContext) {
    Column() {
      if (node.title.length > 0) {
        Text(node.title)
          .fontSize(14)
          .fontColor(AppColors.textSecondary)
          .fontWeight(FontWeight.Bold)
          .padding({ top: 4, bottom: 4 })
      }
      this.RenderChildren(node.children, ctx)
    }
    .width('100%')
    .padding(10)
    .margin({ top: 6, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(AppColors.bgSecondary)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RenderFloat(node: BBNode, flexAlign: FlexAlign, ctx: RenderContext) {
    Row() {
      Column() {
        this.RenderChildren(node.children, ctx)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .justifyContent(flexAlign)
    .margin({ top: 4, bottom: 2 })
  }

  @Builder
  RenderAlign(node: BBNode, ctx: RenderContext) {
    Column() {
      this.RenderChildren(node.children, ctx)
    }
    .width('100%')
    .alignItems(node.align === 'center' ? HorizontalAlign.Center :
      node.align === 'right' ? HorizontalAlign.End : HorizontalAlign.Start)
    .margin({ top: 4, bottom: 2 })
  }

  @Builder
  RenderTable(node: BBNode, ctx: RenderContext) {
    Column() {
      ForEach(node.children, (row: BBNode) => {
        if (row.type === BBNodeType.TABLE_ROW) {
          Row() {
            ForEach(row.children, (cell: BBNode) => {
              if (cell.type === BBNodeType.TABLE_CELL) {
                Column() {
                  this.RenderChildren(cell.children, ctx)
                }
                .padding(6)
                .border({ width: 0.5, color: AppColors.separator })
                .alignItems(HorizontalAlign.Start)
              }
            })
          }
          .width('100%')
        }
      })
    }
    .width('100%')
    .margin({ top: 6, bottom: 4 })
    .border({ width: 0.5, color: AppColors.separator })
    .borderRadius(4)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RenderStyleDiv(node: BBNode, ctx: RenderContext) {
    Column() {
      this.RenderChildren(node.children, ctx)
    }
    .width('100%')
    .margin({ top: 4, bottom: 2 })
    .alignItems(HorizontalAlign.Start)
  }
}

class NodeGroup {
  kind: string = 'inline'
  nodes: BBNode[] = []
}
