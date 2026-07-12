import { MdNode, MdNodeType } from '../../model/MdNode'

/**
 * Markdown 流式友好解析器。
 *
 * 采用全量重解析策略：每次文本更新时重新解析全部累积文本。
 * AI 输出通常 500-3000 字符，O(n) 解析耗时 < 1ms。
 *
 * 解析分两步：
 * 1. 块级解析 (parseBlocks) — 按行识别标题、段落、列表、代码块等
 * 2. 内联解析 (parseInline) — 在文本内识别粗体、斜体、链接等
 *
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  ⚠️  ARKTS 类型标注陷阱 — 后续 AI / 维护者必读  ⚠️       ║
 * ╠══════════════════════════════════════════════════════════════╣
 * ║                                                            ║
 * ║  不要对 regex.exec() 的返回值标注 RegExpMatchArray | null  ║
 * ║  类型！ArkTS 不支持结构类型联合（arkts-no-structural-     ║
 * ║  typing），编译直接报错。                                  ║
 * ║                                                            ║
 * ║  ❌ const m: RegExpMatchArray | null = RE.exec(str)        ║
 * ║  ✅ const m = RE.exec(str)   // 靠类型推断                ║
 * ║                                                            ║
 * ║  同理：不要用 RegExp.test() 后再 exec()，非全局正则会      ║
 * ║  在 test() 中修改 lastIndex 导致 exec() 行为异常。        ║
 * ║  直接用 exec() + null 检查即可。                           ║
 * ╚══════════════════════════════════════════════════════════════╝
 */

/** 标题行正则：`# ` 到 `###### ` */
const HEADING_RE: RegExp = /^(#{1,6})\s+(.+)$/
/** 代码围栏正则：` ``` ` 或 ` ```lang ` */
const FENCE_RE: RegExp = /^```(\w*)\s*$/
/** 无序列表项正则：`- ` / `* ` / `+ ` */
const UL_ITEM_RE: RegExp = /^[-*+]\s+(.+)$/
/** 有序列表项正则：`1. ` */
const OL_ITEM_RE: RegExp = /^(\d+)\.\s+(.+)$/
/** 引用行正则：`> ` 或 `>` */
const BLOCKQUOTE_RE: RegExp = /^>\s?(.*)$/
/** 分隔线正则：3 个以上 `-` / `*` / `_` */
const HR_RE: RegExp = /^[-*_]{3,}\s*$/

/** 表格分隔行单元格正则：`:?---:?` */
const TABLE_SEP_CELL_RE: RegExp = /^:?-{3,}:?$/

/** 行首转义正则：`\*` / `\-` 等 */
const ESCAPE_RE: RegExp = /\\([*_~`#[\]()\-+.!|])/g

/** 块级稳定 key 的序列号计数器，每次 parseMd 调用时重置。 */
let keySerialMap: Record<string, number> = {}

/**
 * 解析 Markdown 文本为 AST 节点数组。
 *
 * 每次文本更新时调用，对流式输出友好。
 *
 * @param text - 完整的累积 Markdown 文本
 * @returns 解析后的 MdNode 数组（顶层为块级节点列表），空文本返回空数组
 */
export function parseMd(text: string): MdNode[] {
  if (text.length === 0) {
    return []
  }
  keySerialMap = {}
  const normalized: string = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  const lines: string[] = normalized.split('\n')
  return parseBlocks(lines)
}

// ============================================================
// 块级解析
// ============================================================

/**
 * 按行扫描识别块级结构并构建块级节点列表。
 *
 * 支持嵌套结构：列表包含列表项，引用块内可递归解析段落。
 *
 * @param lines - 已规范化换行符的文本行数组
 * @returns 块级 MdNode 数组
 */
function parseBlocks(lines: string[]): MdNode[] {
  const result: MdNode[] = []
  const len: number = lines.length
  let i: number = 0

  while (i < len) {
    const line: string = lines[i]

    // 空行 — 块分隔符
    if (line.trim().length === 0) {
      i++
      continue
    }

    // 代码围栏 — 进入代码块模式
    const fenceMatch = FENCE_RE.exec(line)
    if (fenceMatch !== null) {
      const lang: string = fenceMatch[1]
      const fenceResult: CodeFenceResult = consumeCodeFence(lines, i + 1)
      const codeNode: MdNode = new MdNode(MdNodeType.CODE_BLOCK)
      codeNode.text = fenceResult.content
      codeNode.language = lang.length > 0 ? lang : ''
      assignStableKeys(codeNode, buildStableKey('code', fenceResult.content))
      result.push(codeNode)
      i = fenceResult.nextLine
      continue
    }

    // 标题
    const headingMatch = HEADING_RE.exec(line)
    if (headingMatch !== null) {
      const level: number = headingMatch[1].length
      const headingText: string = headingMatch[2]
      const headingNode: MdNode = new MdNode(MdNodeType.HEADING)
      headingNode.level = level
      headingNode.children = parseInline(headingText)
      assignStableKeys(headingNode, buildStableKey('heading', headingText))
      result.push(headingNode)
      i++
      continue
    }

    // 分隔线
    if (HR_RE.test(line)) {
      const hrNode: MdNode = new MdNode(MdNodeType.THEMATIC_BREAK)
      assignStableKeys(hrNode, buildStableKey('hr', ''))
      result.push(hrNode)
      i++
      continue
    }

    // 无序列表
    const ulMatch = UL_ITEM_RE.exec(line)
    if (ulMatch !== null) {
      const listResult: ListResult = consumeList(lines, i, MdNodeType.UNORDERED_LIST)
      let ulContent: string = ''
      for (let j: number = i; j < listResult.nextLine; j++) {
        ulContent += lines[j] + '\n'
      }
      assignStableKeys(listResult.node, buildStableKey('ul', ulContent))
      result.push(listResult.node)
      i = listResult.nextLine
      continue
    }

    // 有序列表
    const olMatch = OL_ITEM_RE.exec(line)
    if (olMatch !== null) {
      const listResult: ListResult = consumeList(lines, i, MdNodeType.ORDERED_LIST)
      let olContent: string = ''
      for (let j: number = i; j < listResult.nextLine; j++) {
        olContent += lines[j] + '\n'
      }
      assignStableKeys(listResult.node, buildStableKey('ol', olContent))
      result.push(listResult.node)
      i = listResult.nextLine
      continue
    }

    // 引用块
    const bqMatch = BLOCKQUOTE_RE.exec(line)
    if (bqMatch !== null) {
      const bqResult: BlockquoteResult = consumeBlockquote(lines, i)
      let bqContent: string = ''
      for (let j: number = i; j < bqResult.nextLine; j++) {
        bqContent += lines[j] + '\n'
      }
      assignStableKeys(bqResult.node, buildStableKey('bq', bqContent))
      result.push(bqResult.node)
      i = bqResult.nextLine
      continue
    }

    // 表格 — 当前行为表格行且下一行为分隔行时确认
    if (isTableRow(line) && i + 1 < len && isTableSeparator(lines[i + 1])) {
      const tableResult: TableResult = consumeTable(lines, i)
      let tableContent: string = ''
      for (let j: number = i; j < tableResult.nextLine; j++) {
        tableContent += lines[j] + '\n'
      }
      assignStableKeys(tableResult.node, buildStableKey('table', tableContent))
      result.push(tableResult.node)
      i = tableResult.nextLine
      continue
    }

    // 普通段落 — 收集连续文本行直到块分隔符
    const paraResult: ParaResult = consumeParagraph(lines, i)
    const paraNode: MdNode = new MdNode(MdNodeType.PARAGRAPH)
    paraNode.children = parseInline(paraResult.text)
    assignStableKeys(paraNode, buildStableKey('para', paraResult.text))
    result.push(paraNode)
    i = paraResult.nextLine
  }

  return result
}

// ============================================================
// 块级辅助结构体
// ============================================================

/** consumeCodeFence 返回值 */
class CodeFenceResult {
  /** 围栏内的代码文本 */
  content: string = ''
  /** 消费结束后下一个待处理行索引 */
  nextLine: number = 0
}

/** consumeList 返回值 */
class ListResult {
  /** 构建的列表节点 */
  node: MdNode = new MdNode(MdNodeType.UNORDERED_LIST)
  /** 消费结束后下一个待处理行索引 */
  nextLine: number = 0
}

/** consumeBlockquote 返回值 */
class BlockquoteResult {
  /** 构建的引用块节点 */
  node: MdNode = new MdNode(MdNodeType.BLOCKQUOTE)
  /** 消费结束后下一个待处理行索引 */
  nextLine: number = 0
}

/** consumeParagraph 返回值 */
class ParaResult {
  /** 段落文本（已合并多行） */
  text: string = ''
  /** 消费结束后下一个待处理行索引 */
  nextLine: number = 0
}

/** consumeTable 返回值 */
class TableResult {
  /** 构建的表格节点 */
  node: MdNode = new MdNode(MdNodeType.TABLE)
  /** 消费结束后下一个待处理行索引 */
  nextLine: number = 0
}

// ============================================================
// 块级消费函数
// ============================================================

/**
 * 消费从 startLine 开始的代码块内容直到闭合围栏或文本末尾。
 *
 * @param lines - 全部文本行
 * @param startLine - 代码块内容起始行号（围栏之后的第一行）
 * @returns 代码文本及下一行索引
 */
function consumeCodeFence(lines: string[], startLine: number): CodeFenceResult {
  const result: CodeFenceResult = new CodeFenceResult()
  const parts: string[] = []
  const len: number = lines.length

  let i: number = startLine
  while (i < len) {
    if (FENCE_RE.test(lines[i])) {
      // 闭合围栏
      i++
      break
    }
    parts.push(lines[i])
    i++
  }

  result.content = parts.join('\n')
  result.nextLine = i
  return result
}

/**
 * 消费从 startLine 开始的连续列表项，构建 UNORDERED_LIST 或 ORDERED_LIST 节点。
 *
 * @param lines - 全部文本行
 * @param startLine - 第一个列表项所在行号
 * @param listType - 列表类型
 * @returns 列表节点及下一行索引
 */
function consumeList(lines: string[], startLine: number, listType: MdNodeType): ListResult {
  const result: ListResult = new ListResult()
  const listNode: MdNode = new MdNode(listType)
  const itemRe: RegExp = listType === MdNodeType.ORDERED_LIST ? OL_ITEM_RE : UL_ITEM_RE
  const len: number = lines.length

  let i: number = startLine
  while (i < len) {
    const line: string = lines[i]

    // 空行 — 列表结束
    if (line.trim().length === 0) {
      break
    }

    const match = itemRe.exec(line)
    if (match === null) {
      break
    }

    // 有序列表正则有两个捕获组 (数字, 内容)，无序列表仅一个 (内容)
    const groupIndex: number = listType === MdNodeType.ORDERED_LIST ? 2 : 1
    const itemText: string = match[groupIndex]
    const itemNode: MdNode = new MdNode(MdNodeType.LIST_ITEM)
    itemNode.children = parseInline(itemText)
    listNode.children.push(itemNode)
    i++
  }

  result.node = listNode
  result.nextLine = i
  return result
}

/**
 * 消费从 startLine 开始的连续引用行，构建 BLOCKQUOTE 节点。
 *
 * 连续的 `> ` 行被合并为一个引用块，各行内容以换行符连接。
 *
 * @param lines - 全部文本行
 * @param startLine - 第一个引用行所在行号
 * @returns 引用块节点及下一行索引
 */
function consumeBlockquote(lines: string[], startLine: number): BlockquoteResult {
  const result: BlockquoteResult = new BlockquoteResult()
  const parts: string[] = []
  const len: number = lines.length

  let i: number = startLine
  while (i < len) {
    const line: string = lines[i]

    if (line.trim().length === 0) {
      // 空行 — 如果下一行仍是引用行则继续，否则结束
      if (i + 1 < len) {
        const bqMatchNext = BLOCKQUOTE_RE.exec(lines[i + 1])
        if (bqMatchNext !== null) {
          parts.push('')
          i++
          continue
        }
      }
      break
    }

    const bqMatch = BLOCKQUOTE_RE.exec(line)
    if (bqMatch === null) {
      break
    }

    parts.push(bqMatch[1])
    i++
  }

  const bqNode: MdNode = new MdNode(MdNodeType.BLOCKQUOTE)
  bqNode.children = parseInline(parts.join('\n'))
  result.node = bqNode
  result.nextLine = i
  return result
}

/**
 * 消费从 startLine 开始的连续文本行，构建段落文本。
 *
 * 段落以空行、块级标记（标题/列表/代码围栏/引用/分隔线）为结束标志。
 * 段落内部的多行以换行符连接，保留软换行。
 *
 * @param lines - 全部文本行
 * @param startLine - 段落起始行号
 * @returns 段落文本及下一行索引
 */
function consumeParagraph(lines: string[], startLine: number): ParaResult {
  const result: ParaResult = new ParaResult()
  const parts: string[] = []
  const len: number = lines.length

  let i: number = startLine
  while (i < len) {
    const line: string = lines[i]

    // 空行 — 段落结束
    if (line.trim().length === 0) {
      break
    }

    // 块级标记 — 段落结束
    if (isBlockStart(line)) {
      break
    }

    parts.push(line)
    i++
  }

  result.text = parts.join('\n')
  result.nextLine = i
  return result
}

// ============================================================
// 表格解析
// ============================================================

/**
 * 判断一行是否为表格行（至少包含一个 `|` 分隔符）。
 *
 * 首尾 `|` 可选，内部至少有一个 `|` 用于分隔单元格。
 *
 * @param line - 待判断的文本行
 * @returns 如果是表格行返回 true
 */
function isTableRow(line: string): boolean {
  const trimmed: string = line.trim()
  if (trimmed.length === 0) {
    return false
  }
  // 至少包含一个 |，split 后排除首尾空段至少有两段非空内容
  const parts: string[] = trimmed.split('|')
  let nonEmptyCount: number = 0
  for (let i: number = 0; i < parts.length; i++) {
    if (parts[i].trim().length > 0) {
      nonEmptyCount++
    }
  }
  return nonEmptyCount >= 2
}

/**
 * 判断一行是否为表格分隔行。
 *
 * 每个 `|` 分隔的单元格必须匹配 `:?-{3,}:?` 格式。
 *
 * @param line - 待判断的文本行
 * @returns 如果是表格分隔行返回 true
 */
function isTableSeparator(line: string): boolean {
  const trimmed: string = line.trim()
  if (trimmed.length === 0) {
    return false
  }
  const cells: string[] = parseTableCells(trimmed)
  if (cells.length === 0) {
    return false
  }
  for (let i: number = 0; i < cells.length; i++) {
    if (!TABLE_SEP_CELL_RE.test(cells[i])) {
      return false
    }
  }
  return true
}

/**
 * 按 `|` 拆分表格行，返回去除首尾空白后的单元格文本数组。
 *
 * 处理首尾可选 `|`：自动剥离行首/行尾的 `|` 后再拆分。
 *
 * @param line - 表格行文本
 * @returns 单元格文本数组
 */
function parseTableCells(line: string): string[] {
  let trimmed: string = line.trim()
  // 剥离首尾可选 |
  if (trimmed.startsWith('|')) {
    trimmed = trimmed.substring(1)
  }
  if (trimmed.endsWith('|')) {
    trimmed = trimmed.substring(0, trimmed.length - 1)
  }
  const parts: string[] = trimmed.split('|')
  const cells: string[] = []
  for (let i: number = 0; i < parts.length; i++) {
    cells.push(parts[i].trim())
  }
  return cells
}

/**
 * 解析表格分隔行中各列的对齐方式。
 *
 * @param sepLine - 表格分隔行文本
 * @returns 对齐方式数组（'left' | 'center' | 'right'）
 */
function parseCellAlignments(sepLine: string): string[] {
  const cells: string[] = parseTableCells(sepLine)
  const alignments: string[] = []
  for (let i: number = 0; i < cells.length; i++) {
    const cell: string = cells[i]
    const left: boolean = cell.startsWith(':')
    const right: boolean = cell.endsWith(':')
    if (left && right) {
      alignments.push('center')
    } else if (right) {
      alignments.push('right')
    } else {
      alignments.push('left')
    }
  }
  return alignments
}

/**
 * 消费从 startLine 开始的完整表格，构建 TABLE 节点。
 *
 * GFM 表格结构：
 * 1. 表头行（必选）
 * 2. 分隔行（必选，含对齐信息）
 * 3. 零或多行数据行
 * 表格以空行或非表格行结束。
 *
 * @param lines - 全部文本行
 * @param startLine - 表头行所在行号
 * @returns 表格节点及下一行索引
 */
function consumeTable(lines: string[], startLine: number): TableResult {
  const result: TableResult = new TableResult()
  const tableNode: MdNode = new MdNode(MdNodeType.TABLE)
  const len: number = lines.length

  // 解析表头行
  const headerCells: string[] = parseTableCells(lines[startLine])
  if (headerCells.length === 0) {
    result.node = tableNode
    result.nextLine = startLine + 1
    return result
  }

  // 解析分隔行 → 获取各列对齐方式
  let alignments: string[] = []
  let i: number = startLine + 1
  if (i < len && isTableSeparator(lines[i])) {
    alignments = parseCellAlignments(lines[i])
    i++
  }

  // 对齐数组长度补齐至列数
  while (alignments.length < headerCells.length) {
    alignments.push('left')
  }

  // 构建表头行节点
  const headerRow: MdNode = new MdNode(MdNodeType.TABLE_ROW)
  for (let c: number = 0; c < headerCells.length; c++) {
    const cellNode: MdNode = new MdNode(MdNodeType.TABLE_CELL)
    cellNode.align = alignments[c]
    cellNode.children = parseInline(headerCells[c])
    headerRow.children.push(cellNode)
  }
  tableNode.children.push(headerRow)

  // 消费数据行
  while (i < len) {
    const line: string = lines[i]

    // 空行 — 表格结束
    if (line.trim().length === 0) {
      break
    }

    // 非表格行 — 表格结束
    if (!isTableRow(line)) {
      break
    }

    const dataCells: string[] = parseTableCells(line)
    if (dataCells.length === 0) {
      break
    }

    const dataRow: MdNode = new MdNode(MdNodeType.TABLE_ROW)
    const cellCount: number = dataCells.length < headerCells.length ? dataCells.length : headerCells.length
    for (let c: number = 0; c < cellCount; c++) {
      const cellNode: MdNode = new MdNode(MdNodeType.TABLE_CELL)
      cellNode.align = c < alignments.length ? alignments[c] : 'left'
      cellNode.children = parseInline(dataCells[c])
      dataRow.children.push(cellNode)
    }
    tableNode.children.push(dataRow)
    i++
  }

  result.node = tableNode
  result.nextLine = i
  return result
}

/**
 * 判断一行文本是否为块级结构的起始行。
 *
 * @param line - 待判断的文本行
 * @returns 如果是块级起始行返回 true
 */
function isBlockStart(line: string): boolean {
  return HEADING_RE.test(line) ||
    FENCE_RE.test(line) ||
    UL_ITEM_RE.test(line) ||
    OL_ITEM_RE.test(line) ||
    BLOCKQUOTE_RE.test(line) ||
    HR_RE.test(line) ||
    isTableRow(line)
}

// ============================================================
// 内联解析
// ============================================================

/**
 * 解析文本中的内联格式，返回内联节点列表。
 *
 * 采用递归下降策略：在 BOLD/ITALIC/STRIKETHROUGH 内部
 * 再次调用 parseInline 实现嵌套格式（如 `**粗体中的 *斜体***`）。
 *
 * 流式友好：未闭合的标记（如 `**未闭合）按普通文本处理，
 * 下次收到更多文本时全量重解析会自动修正。
 *
 * @param text - 待解析的文本（不含块级标记）
 * @returns 内联 MdNode 数组
 */
export function parseInline(text: string): MdNode[] {
  const result: MdNode[] = []
  const len: number = text.length

  // 空文本直接返回空数组
  if (len === 0) {
    return result
  }

  let pos: number = 0
  // 当前待刷新的纯文本段起始位置
  let textStart: number = 0

  while (pos < len) {
    const ch: string = text.charAt(pos)

    // 转义字符 — 跳过反斜杠，下一个字符作为普通文本
    if (ch === '\\' && pos + 1 < len) {
      // 刷新转义符之前的文本
      flushText(text, textStart, pos, result)
      // 将转义后的字符作为 TEXT 节点
      const escapedNode: MdNode = new MdNode(MdNodeType.TEXT)
      escapedNode.text = text.charAt(pos + 1)
      result.push(escapedNode)
      pos += 2
      textStart = pos
      continue
    }

    // 行内代码 `` `code` ``
    if (ch === '`') {
      const end: number = text.indexOf('`', pos + 1)
      if (end >= 0) {
        flushText(text, textStart, pos, result)
        const codeNode: MdNode = new MdNode(MdNodeType.CODE_INLINE)
        codeNode.text = text.substring(pos + 1, end)
        result.push(codeNode)
        pos = end + 1
        textStart = pos
        continue
      }
      // 未闭合的反引号 — 当作普通文本继续
      pos++
      continue
    }

    // 粗体 `**text**`（优先于斜体）
    if (ch === '*' && pos + 1 < len && text.charAt(pos + 1) === '*') {
      const end: number = text.indexOf('**', pos + 2)
      if (end >= 0) {
        flushText(text, textStart, pos, result)
        const innerText: string = text.substring(pos + 2, end)
        const boldNode: MdNode = new MdNode(MdNodeType.BOLD)
        boldNode.children = parseInline(innerText)
        // 优化：单 TEXT 子节点时提升文本到父节点
        compressSingleTextChild(boldNode)
        result.push(boldNode)
        pos = end + 2
        textStart = pos
        continue
      }
      // 未闭合 — 当作普通文本继续
      pos += 2
      continue
    }

    // 斜体 `*text*`（单星号，不匹配 `**`）
    if (ch === '*') {
      const end: number = findSingleCharMarker(text, '*', pos + 1, len)
      if (end >= 0) {
        flushText(text, textStart, pos, result)
        const innerText: string = text.substring(pos + 1, end)
        const italicNode: MdNode = new MdNode(MdNodeType.ITALIC)
        italicNode.children = parseInline(innerText)
        compressSingleTextChild(italicNode)
        result.push(italicNode)
        pos = end + 1
        textStart = pos
        continue
      }
      // 未闭合 — 当作普通文本
      pos++
      continue
    }

    // 删除线 `~~text~~`
    if (ch === '~' && pos + 1 < len && text.charAt(pos + 1) === '~') {
      const end: number = text.indexOf('~~', pos + 2)
      if (end >= 0) {
        flushText(text, textStart, pos, result)
        const innerText: string = text.substring(pos + 2, end)
        const strikeNode: MdNode = new MdNode(MdNodeType.STRIKETHROUGH)
        strikeNode.children = parseInline(innerText)
        compressSingleTextChild(strikeNode)
        result.push(strikeNode)
        pos = end + 2
        textStart = pos
        continue
      }
      // 未闭合 — 当作普通文本
      pos += 2
      continue
    }

    // 链接 `[text](url)`
    if (ch === '[') {
      const linkEnd: number = findLinkClose(text, pos, len)
      if (linkEnd >= 0) {
        const closeBracket: number = text.indexOf(']', pos + 1)
        flushText(text, textStart, pos, result)
        const linkText: string = text.substring(pos + 1, closeBracket)
        const linkUrl: string = text.substring(closeBracket + 2, linkEnd)
        const linkNode: MdNode = new MdNode(MdNodeType.LINK)
        linkNode.text = linkText
        linkNode.href = linkUrl
        result.push(linkNode)
        pos = linkEnd + 1
        textStart = pos
        continue
      }
      // 不是合法链接 — 当作普通文本
      pos++
      continue
    }

    // 无标记匹配，前进一个字符
    pos++
  }

  // 刷新尾部剩余文本
  flushText(text, textStart, len, result)

  return result
}

/**
 * 将 text[start..end] 段作为 TEXT 节点追加到 result（如果非空）。
 *
 * @param text - 源文本
 * @param start - 段起始位置
 * @param end - 段结束位置（不含）
 * @param result - 目标节点数组
 */
function flushText(text: string, start: number, end: number, result: MdNode[]): void {
  if (end > start) {
    const textNode: MdNode = new MdNode(MdNodeType.TEXT)
    textNode.text = text.substring(start, end)
    result.push(textNode)
  }
}

/**
 * 查找单字符标记（`*`）的闭合位置。
 *
 * 与双字符标记（`**`、`~~`）不同，单字符 `*` 需要跳过连续的 `**`，
 * 避免将 `**bold**` 中的起始 `*` 误匹配。
 *
 * @param text - 源文本
 * @param marker - 标记字符
 * @param from - 搜索起始位置
 * @param len - 文本长度
 * @returns 闭合位置，-1 表示未找到
 */
function findSingleCharMarker(text: string, marker: string, from: number, len: number): number {
  let i: number = from
  while (i < len) {
    if (text.charAt(i) === marker) {
      // 如果下一个字符也是 marker，说明这是双字符标记的一部分，跳过
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

/**
 * 查找链接闭合位置 `[text](url)`。
 *
 * 匹配 `]` 后紧跟 `(` 和 `)` 的完整链接语法。
 *
 * @param text - 源文本
 * @param openPos - `[` 的位置
 * @param len - 文本长度
 * @returns `)` 的位置，-1 表示不是合法链接
 */
function findLinkClose(text: string, openPos: number, len: number): number {
  const closeBracket: number = text.indexOf(']', openPos + 1)
  if (closeBracket < 0) {
    return -1
  }
  // 必须紧跟 `(`
  if (closeBracket + 1 >= len || text.charAt(closeBracket + 1) !== '(') {
    return -1
  }
  const closeParen: number = text.indexOf(')', closeBracket + 2)
  if (closeParen < 0) {
    return -1
  }
  return closeParen
}

/**
 * 优化：如果节点仅有一个 TEXT 子节点，将文本提升到父节点 text 字段并清空 children。
 *
 * 此优化减少树深度，简化渲染层的工作量（与 BBNode 的 inline-parser 做法一致）。
 *
 * @param node - 待优化的父节点（BOLD / ITALIC / STRIKETHROUGH）
 */
function compressSingleTextChild(node: MdNode): void {
  if (node.children.length === 1 && node.children[0].type === MdNodeType.TEXT) {
    node.text = node.children[0].text
    node.children = []
  }
}

/**
 * 32-bit FNV-1a 哈希，输出 36 进制短字符串。
 *
 * 用于从块内容生成稳定的 ForEach key，避免行号漂移
 * 导致组件实例全量重建。
 *
 * @param str - 待哈希字符串
 * @returns 36 进制哈希字符串
 */
function hashString(str: string): string {
  let hash: number = 0
  for (let i: number = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i)
    hash |= 0
  }
  return (hash >>> 0).toString(36)
}

/**
 * 构建基于块类型和内容的稳定 key。
 *
 * 使用内容哈希作为主 key，块类型序列号作为后缀
 * 防止相同内容块的 key 冲突。
 *
 * @param prefix - 块类型前缀
 * @param content - 块文本内容
 * @returns 稳定 key
 */
function buildStableKey(prefix: string, content: string): string {
  const serial: number = (keySerialMap[prefix] ?? 0) + 1
  keySerialMap[prefix] = serial
  if (content.length > 0) {
    return prefix + '_' + hashString(content) + '_' + serial.toString()
  }
  return prefix + '_' + serial.toString()
}

/**
 * 为节点及其子节点递归分配稳定 key。
 *
 * @param node - 待分配 key 的节点
 * @param key - 当前节点 key
 */
function assignStableKeys(node: MdNode, key: string): void {
  node.key = key
  for (let i: number = 0; i < node.children.length; i++) {
    const child: MdNode = node.children[i]
    assignStableKeys(child, key + '_' + child.type.toString() + '_' + i.toString())
  }
}
