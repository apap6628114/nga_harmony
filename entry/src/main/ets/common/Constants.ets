/**
 * 颜色和常量定义
 */

// ============== 主题定义 ==============

export interface AppColorSet {
  primary: string
  primaryLight: string
  destructive: string
  warning: string
  success: string
  bg: string
  bgSecondary: string
  bgTertiary: string
  textPrimary: string
  textSecondary: string
  textTertiary: string
  separator: string
  dividerStrong: string
  white: string
  black: string
  overlay: string
  overlayStrong: string
  shadow: string
  shadowLight: string
  toastBg: string
  imageViewerBg: string
  warnBg: string
  warnBorder: string
  warnText: string
  chevron: string
  sheetIndicator: string
  quoteBorders: string[]
}

const ORIGINAL_COLORS: AppColorSet = {
  primary: '#C08A4A',
  primaryLight: '#FDF3E7',
  destructive: '#E45D4C',
  warning: '#E8933A',
  success: '#7BA05B',
  bg: '#FEFAF6',
  bgSecondary: '#F5EDE3',
  bgTertiary: '#FDF7F0',
  textPrimary: '#3E2A1D',
  textSecondary: '#9C8B7A',
  textTertiary: '#C4B5A0',
  separator: '#E8DCC8',
  dividerStrong: '#D0C0A8',
  white: '#FFFFFF',
  black: '#000000',
  overlay: '#33000000',
  overlayStrong: '#66000000',
  shadow: '#40000000',
  shadowLight: '#30000000',
  toastBg: '#CC000000',
  imageViewerBg: '#FF000000',
  warnBg: '#FFF2E5',
  warnBorder: '#E8B98A',
  warnText: '#A65D2E',
  chevron: '#C4B5A0',
  sheetIndicator: '#D4C8B0',
  quoteBorders: [
    'rgba(192, 138, 74, 0.3)',
    'rgba(192, 138, 74, 0.2)',
    'rgba(192, 138, 74, 0.12)',
  ],
}

const LIGHT_COLORS: AppColorSet = {
  primary: '#007AFF',
  primaryLight: '#E8F2FF',
  destructive: '#FF3B30',
  warning: '#FF9500',
  success: '#34C759',
  bg: '#FFFFFF',
  bgSecondary: '#F2F2F7',
  bgTertiary: '#F9F9F9',
  textPrimary: '#1C1C1E',
  textSecondary: '#8E8E93',
  textTertiary: '#AEAEB2',
  separator: '#E5E5EA',
  dividerStrong: '#C0C0C4',
  white: '#FFFFFF',
  black: '#000000',
  overlay: '#33000000',
  overlayStrong: '#66000000',
  shadow: '#40000000',
  shadowLight: '#30000000',
  toastBg: '#CC000000',
  imageViewerBg: '#FF000000',
  warnBg: '#FFF3E0',
  warnBorder: '#FFB74D',
  warnText: '#8B0000',
  chevron: '#C7C7CC',
  sheetIndicator: '#D1D1D6',
  quoteBorders: [
    'rgba(0, 122, 255, 0.3)',
    'rgba(0, 122, 255, 0.2)',
    'rgba(0, 122, 255, 0.12)',
  ],
}

// 当前激活的主题色（运行时可变，组件直接使用）
export class AppColors {
  static primary: string = ORIGINAL_COLORS.primary
  static primaryLight: string = ORIGINAL_COLORS.primaryLight
  static destructive: string = ORIGINAL_COLORS.destructive
  static warning: string = ORIGINAL_COLORS.warning
  static success: string = ORIGINAL_COLORS.success
  static bg: string = ORIGINAL_COLORS.bg
  static bgSecondary: string = ORIGINAL_COLORS.bgSecondary
  static bgTertiary: string = ORIGINAL_COLORS.bgTertiary
  static textPrimary: string = ORIGINAL_COLORS.textPrimary
  static textSecondary: string = ORIGINAL_COLORS.textSecondary
  static textTertiary: string = ORIGINAL_COLORS.textTertiary
  static separator: string = ORIGINAL_COLORS.separator
  static dividerStrong: string = ORIGINAL_COLORS.dividerStrong
  static white: string = ORIGINAL_COLORS.white
  static black: string = ORIGINAL_COLORS.black
  static overlay: string = ORIGINAL_COLORS.overlay
  static overlayStrong: string = ORIGINAL_COLORS.overlayStrong
  static shadow: string = ORIGINAL_COLORS.shadow
  static shadowLight: string = ORIGINAL_COLORS.shadowLight
  static toastBg: string = ORIGINAL_COLORS.toastBg
  static imageViewerBg: string = ORIGINAL_COLORS.imageViewerBg
  static warnBg: string = ORIGINAL_COLORS.warnBg
  static warnBorder: string = ORIGINAL_COLORS.warnBorder
  static warnText: string = ORIGINAL_COLORS.warnText
  static chevron: string = ORIGINAL_COLORS.chevron
  static sheetIndicator: string = ORIGINAL_COLORS.sheetIndicator
  static quoteBorders: string[] = [
    ORIGINAL_COLORS.quoteBorders[0],
    ORIGINAL_COLORS.quoteBorders[1],
    ORIGINAL_COLORS.quoteBorders[2],
  ]
}

// 将指定主题的色值同步到 AppColors（运行时切换）
export function applyTheme(name: string): void {
  let src: AppColorSet
  if (name === 'white') {
    src = LIGHT_COLORS
  } else {
    src = ORIGINAL_COLORS
  }
  AppColors.primary = src.primary
  AppColors.primaryLight = src.primaryLight
  AppColors.destructive = src.destructive
  AppColors.warning = src.warning
  AppColors.success = src.success
  AppColors.bg = src.bg
  AppColors.bgSecondary = src.bgSecondary
  AppColors.bgTertiary = src.bgTertiary
  AppColors.textPrimary = src.textPrimary
  AppColors.textSecondary = src.textSecondary
  AppColors.textTertiary = src.textTertiary
  AppColors.separator = src.separator
  AppColors.dividerStrong = src.dividerStrong
  AppColors.white = src.white
  AppColors.black = src.black
  AppColors.overlay = src.overlay
  AppColors.overlayStrong = src.overlayStrong
  AppColors.shadow = src.shadow
  AppColors.shadowLight = src.shadowLight
  AppColors.toastBg = src.toastBg
  AppColors.imageViewerBg = src.imageViewerBg
  AppColors.warnBg = src.warnBg
  AppColors.warnBorder = src.warnBorder
  AppColors.warnText = src.warnText
  AppColors.chevron = src.chevron
  AppColors.sheetIndicator = src.sheetIndicator
  AppColors.quoteBorders[0] = src.quoteBorders[0]
  AppColors.quoteBorders[1] = src.quoteBorders[1]
  AppColors.quoteBorders[2] = src.quoteBorders[2]
}

// 主题元数据
export interface ThemeOption {
  name: string
  label: string
  primaryColor: string
  bgColor: string
}

export const THEME_OPTIONS: ThemeOption[] = [
  { name: 'original', label: '原味主题', primaryColor: '#C08A4A', bgColor: '#FEFAF6' },
  { name: 'white', label: '白色主题', primaryColor: '#007AFF', bgColor: '#FFFFFF' },
]

// 品牌图标背景色（不随主题变化）
export class IconColors {
  static readonly mail: string = '#007AFF'
  static readonly bell: string = '#FF3B30'
  static readonly star: string = '#FF9500'
  static readonly clock: string = '#8E8E93'
  static readonly checkin: string = '#34C759'
  static readonly settings: string = '#5856D6'
  static readonly moon: string = '#5856D6'
  static readonly textFields: string = '#FF2D55'
  static readonly globe: string = '#5AC8FA'
  static readonly block: string = '#8E8E93'
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
  2: '#C08A4A',  // gold
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
  label: string
  category: string // 'thread' | 'message'
}

export const NOTI_TYPE_MAP: Record<number, NotiTypeInfo> = {
  1: { label: '回复了你的主题', category: 'thread' },
  2: { label: '回复了你的帖子', category: 'thread' },
  3: { label: '评论了你的主题', category: 'thread' },
  4: { label: '评论了你的帖子', category: 'thread' },
  7: { label: '在主题中@了你', category: 'thread' },
  8: { label: '在帖子中@了你', category: 'thread' },
  10: { label: '给你发了私信', category: 'message' },
  11: { label: '回复了你的私信', category: 'message' },
}

export function getNotiIcon(type: number): Resource {
  const map: Record<number, Resource> = {
    1: $r('app.media.icon_chat_bubble'),
    2: $r('app.media.icon_chat_bubble'),
    3: $r('app.media.icon_chat_bubble'),
    4: $r('app.media.icon_chat_bubble'),
    7: $r('app.media.icon_at'),
    8: $r('app.media.icon_at'),
    10: $r('app.media.icon_mail'),
    11: $r('app.media.icon_mail'),
  }
  return map[type] || $r('app.media.icon_clipboard')
}
