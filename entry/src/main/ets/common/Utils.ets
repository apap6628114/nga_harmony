/**
 * 通用工具函数 - 从 React lib/utils.ts 迁移
 */

export function formatTime(ts: number | string): string {
  if (!ts) return ''
  const numTs = typeof ts === 'string' ? Number(ts) : ts
  if (isNaN(numTs)) return String(ts)
  const d = new Date(numTs > 1e12 ? numTs : numTs * 1000)
  if (isNaN(d.getTime())) return String(ts)
  const diff = Date.now() - d.getTime()
  if (diff < 60000) return '刚刚'
  if (diff < 3600000) return `${Math.floor(diff / 60000)}分钟前`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}小时前`
  if (diff < 2592000000) return `${Math.floor(diff / 86400000)}天前`
  const isThisYear = d.getFullYear() === new Date().getFullYear()
  if (isThisYear) {
    return `${d.getMonth() + 1}-${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  }
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getDate()}`
}

export function fmtNum(n: string | number): string {
  const num = Number(n)
  if (isNaN(num)) return String(n)
  if (num >= 10000) return (num / 10000).toFixed(1) + 'w'
  if (num >= 1000) return (num / 1000).toFixed(1) + 'k'
  return String(num)
}

export function escHtml(s: string): string {
  if (!s) return ''
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

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
    .replace(/&#(\d+);/g, (_s: string, c: string): string => {
      const code: number = parseInt(c, 10)
      if (code <= 0xFFFF) return String.fromCharCode(code)
      const hi: number = 0xD800 + ((code - 0x10000) >> 10)
      const lo: number = 0xDC00 + ((code - 0x10000) & 0x3FF)
      return String.fromCharCode(hi) + String.fromCharCode(lo)
    })
}

export function getAvatarUrl(avatar: string, uid?: number | string): string {
  if (!avatar) return ''
  if (avatar.startsWith('http')) return avatar
  if (avatar.startsWith('/')) return `https://img.nga.178.com${avatar}`
  return `https://img4.nga.178.com/ngabbs/nga_classic/avatar/${avatar}`
}

export function stripThumbnailSuffix(url: string): string {
  let result: string = url
    .replace(/\.thumb_s(\.\w+)$/i, '$1')
    .replace(/\.thumb_m(\.\w+)$/i, '$1')
    .replace(/\.medium(\.\w+)$/i, '$1')
    .replace(/\.thumb(\.\w+)$/i, '$1')
  const dot: number = result.lastIndexOf('.')
  if (dot > 0) {
    const ext: string = result.substring(dot)
    const prev: string = result.substring(0, dot)
    if (prev.endsWith(ext)) {
      result = prev
    }
  }
  return result
}

/**
 * 根据 name 生成 HSL 色相值（用于头像背景色）
 */
export function nameToHue(name: string): number {
  const n = name || '?'
  let acc = 0
  for (let i = 0; i < n.length; i++) {
    acc += n.charCodeAt(i)
  }
  return acc % 360
}

/**
 * HSL 转 HEX 颜色（ArkUI 不支持 hsl() 字符串，需转换为 #RRGGBB）
 */
export function hslToHex(h: number, s: number, l: number): string {
  const sNorm = s / 100
  const lNorm = l / 100
  const a = sNorm * Math.min(lNorm, 1 - lNorm)
  const f = (n: number): string => {
    const k = (n + h / 30) % 12
    const color = lNorm - a * Math.max(Math.min(k - 3, 9 - k, 1), -1)
    return Math.round(255 * Math.max(0, Math.min(1, color))).toString(16).padStart(2, '0')
  }
  return `#${f(0)}${f(8)}${f(4)}`
}

/**
 * 获取名称首字母
 */
export function getInitial(name: string): string {
  const ch = (name || '?').charAt(0).toUpperCase()
  return ch || '?'
}
