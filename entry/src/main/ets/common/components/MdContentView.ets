import { MdNode } from '../../model/MdNode'
import { parseMd } from '../../parser/md/MdParser'
import { MdNodesView } from './MdNodesView'

/**
 * Markdown 内容渲染组件。
 *
 * 接收原始 Markdown 文本，解析为 AST 后交给 MdNodesView 渲染。
 */
@Component
export struct MdContentView {
  /** 原始 Markdown 文本。 */
  @Prop @Watch('onTextChange') text: string = ''
  /** 链接点击回调。 */
  onLinkClick: (href: string) => void = (_href: string) => {}

  /** 解析后的 AST 节点缓存。 */
  @State private parsedNodes: MdNode[] = []

  /**
   * 文本变化时重新解析 AST。
   */
  private onTextChange(): void {
    this.parsedNodes = parseMd(this.text)
  }

  /**
   * 组件出现时初始化 AST。
   */
  aboutToAppear(): void {
    this.parsedNodes = parseMd(this.text)
  }

  /**
   * 构建 Markdown 内容视图。
   */
  build() {
    MdNodesView({
      nodes: this.parsedNodes,
      onLinkClick: this.onLinkClick
    })
  }
}
