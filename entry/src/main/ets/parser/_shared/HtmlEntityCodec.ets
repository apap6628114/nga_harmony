/**
 * HTML 实体解码统一工具
 *
 * 项目内存在两类语义不同的解码需求，此处集中导出，避免多份重复实现：
 * - `decodeHtmlEntities`：BBCode 帖子正文解码。除标准实体外，还需把 `<br>` 转为换行、
 *   剥离残余 HTML 标签，因为 BBCode 解析器以纯文本切片为单位处理。
 * - `unescapeHtml`：纯文本字段（用户名、标题、签名、消息内容等）解码，仅反转实体，
 *   不触碰 `<`、标签或换行，避免吞掉合法文本。
 *
 * 两者都支持 `&#91;` / `&#93;` / `&nbsp;` / `&#十进制;` / `&#x十六进制;`（含 BMP 之外代理对编码）。
 */

/**
 * 把单个码点转为字符串，码点在 BMP 之外时输出 UTF-16 代理对。
 *
 * @param code Unicode 码点
 * @returns 对应字符（含代理对）
 */
function fromCodePoint(code: number): string {
  if (code <= 0xFFFF) return String.fromCharCode(code)
  const hi: number = 0xD800 + ((code - 0x10000) >> 10)
  const lo: number = 0xDC00 + ((code - 0x10000) & 0x3FF)
  return String.fromCharCode(hi) + String.fromCharCode(lo)
}

/**
 * 反转 HTML 实体为字符，不处理标签或换行。适用于纯文本字段显示。
 *
 * @param s 待解码字符串
 * @returns 解码后的字符串
 */
export function unescapeHtml(s: string): string {
  if (!s) return ''
  return s
    .replace(/&#91;/g, '[')
    .replace(/&#93;/g, ']')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, '/')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_s: string, c: string): string => fromCodePoint(parseInt(c, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_s: string, hex: string): string => fromCodePoint(parseInt(hex, 16)))
}

/**
 * 反转 HTML 实体并规范化 BBCode 正文：`<br>` 转换行、剥离残余 HTML 标签。
 * 仅用于 BBCode 解析路径。
 *
 * @param s 待解码的 BBCode 正文片段
 * @returns 解码并清理后的文本
 */
export function decodeHtmlEntities(s: string): string {
  return s
    .replace(/&#91;/g, '[')
    .replace(/&#93;/g, ']')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, '/')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_s: string, c: string): string => fromCodePoint(parseInt(c, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_s: string, hex: string): string => fromCodePoint(parseInt(hex, 16)))
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
}
