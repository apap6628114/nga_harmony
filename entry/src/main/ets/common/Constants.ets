/**
 * 颜色和常量定义
 */

// 主题色
export class AppColors {
  static readonly primary: string = '#007AFF'
  static readonly primaryLight: string = '#E8F2FF'
  static readonly destructive: string = '#FF3B30'
  static readonly warning: string = '#FF9500'
  static readonly success: string = '#34C759'
  static readonly bg: string = '#FFFFFF'
  static readonly bgSecondary: string = '#F2F2F7'
  static readonly bgTertiary: string = '#F9F9F9'
  static readonly textPrimary: string = '#1C1C1E'
  static readonly textSecondary: string = '#8E8E93'
  static readonly textTertiary: string = '#AEAEB2'
  static readonly separator: string = '#E5E5EA'
  static readonly dividerStrong: string = '#C0C0C4'
  static readonly white: string = '#FFFFFF'
  static readonly black: string = '#000000'
}

// 深色模式颜色
export class AppColorsDark {
  static readonly primary: string = '#0A84FF'
  static readonly primaryLight: string = '#1C2B3A'
  static readonly destructive: string = '#FF453A'
  static readonly warning: string = '#FF9F0A'
  static readonly success: string = '#30D158'
  static readonly bg: string = '#000000'
  static readonly bgSecondary: string = '#1C1C1E'
  static readonly bgTertiary: string = '#2C2C2E'
  static readonly textPrimary: string = '#F2F2F7'
  static readonly textSecondary: string = '#98989D'
  static readonly textTertiary: string = '#636366'
  static readonly separator: string = '#38383A'
  static readonly dividerStrong: string = '#545458'
  static readonly white: string = '#FFFFFF'
  static readonly black: string = '#000000'
}

// 字号选项
export interface FontOption {
  label: string
  value: number
}

export const FONT_OPTIONS: FontOption[] = [
  { label: '小', value: 13 },
  { label: '中', value: 15 },
  { label: '大', value: 17 },
  { label: '特大', value: 19 },
]

// 域名选项
export interface DomainOption {
  label: string
  value: number
}

export const DOMAIN_OPTIONS: DomainOption[] = [
  { label: 'bbs.nga.cn', value: 0 },
  { label: 'ngabbs.com', value: 1 },
  { label: 'nga.178.com', value: 2 },
]

// 标题字体颜色映射
export const FONT_COLORS: Record<number, string> = {
  1: '#FF3B30',  // red
  2: '#007AFF',  // blue
  4: '#34C759',  // green
  8: '#FF9500',  // orange
  16: '#8E8E93', // gray
}

// 排序模式
export interface SortMode {
  key: string
  label: string
}

export const SORT_MODES: SortMode[] = [
  { key: 'latest', label: '最新' },
  { key: 'recommend', label: '推荐' },
  { key: 'hot', label: '24h热门' },
]

// ============== 响应式断点 ==============

export class BreakpointConstants {
  static readonly BREAKPOINT_SM: string = 'sm'
  static readonly BREAKPOINT_MD: string = 'md'
  static readonly BREAKPOINT_LG: string = 'lg'
  static readonly CURRENT_BREAKPOINT: string = 'currentBreakpoint'
}

// 断点值工具类，根据当前断点返回不同值
export class BreakpointType<T> {
  readonly sm: T
  readonly md: T
  readonly lg: T

  constructor(sm: T, md: T, lg: T) {
    this.sm = sm
    this.md = md
    this.lg = lg
  }

  getValue(breakpoint: string): T {
    if (breakpoint === 'md') {
      return this.md
    }
    if (breakpoint === 'lg') {
      return this.lg
    }
    return this.sm
  }
}

// 通知类型映射
export interface NotiTypeInfo {
  icon: string
  label: string
  category: string // 'thread' | 'message'
}

export const NOTI_TYPE_MAP: Record<number, NotiTypeInfo> = {
  1: { icon: '💬', label: '回复了你的主题', category: 'thread' },
  2: { icon: '💬', label: '回复了你的帖子', category: 'thread' },
  3: { icon: '💬', label: '评论了你的主题', category: 'thread' },
  4: { icon: '💬', label: '评论了你的帖子', category: 'thread' },
  7: { icon: '@', label: '在主题中@了你', category: 'thread' },
  8: { icon: '@', label: '在帖子中@了你', category: 'thread' },
  10: { icon: '✉️', label: '给你发了私信', category: 'message' },
  11: { icon: '✉️', label: '回复了你的私信', category: 'message' },
}
