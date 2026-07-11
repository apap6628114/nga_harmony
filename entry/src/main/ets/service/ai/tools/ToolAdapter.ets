/**
 * 工具适配器接口与公共类型。
 *
 * 定义 Tool Registry 模式中每个工具的契约，
 * 以及服务层与 UI 层之间的状态传递类型。
 */

import type { ToolCall } from '../OpenAiCompatibleClient'
import type { ChatMessage } from '../OpenAiCompatibleClient'

/**
 * 工具执行结果。
 *
 * 由各工具适配器返回，服务层将其注入模型对话上下文。
 */
export class ToolResult {
  /** 执行是否成功 */
  success: boolean = false
  /** 注入给模型的上下文字符串 */
  content: string = ''
  /** 错误信息 */
  errorMessage: string = ''
  /** UI 展示摘要文本 */
  summary: string = ''
  /** UI 结果计数 */
  count: number = 0
}

/**
 * 工具适配器接口。
 *
 * 每个 Function Calling 工具实现此接口，
 * 声明自己的 OpenAI 工具定义、可用性判断及执行逻辑。
 */
export interface ToolAdapter {
  /**
   * 获取此工具的 OpenAI Function Calling 定义。
   *
   * @returns 符合 OpenAI tools 数组元素格式的对象
   */
  getDefinition(): Object

  /**
   * 判断此工具当前是否可用。
   *
   * 例如：WebSearchTool 在用户激活了搜索提供商时可用。
   *
   * @returns true 表示工具可被加入当前请求的 tools 声明
   */
  isAvailable(): boolean

  /**
   * 执行工具调用。
   *
   * @param toolCall - 模型发起的工具调用
   * @param messages - 当前对话消息列表（用于上下文推断）
   * @returns 工具执行结果
   */
  execute(toolCall: ToolCall, messages: ChatMessage[]): Promise<ToolResult>
}

/**
 * 工具调用阶段信息，用于 UI 展示工具调用的进度与详情。
 *
 * @property phase - 当前阶段: '' | 'analyzing' | 'executing' | 'compiling' | 'complete'
 * @property toolName - 工具名称（如 'web_search'）
 * @property summary - UI 摘要文本
 * @property count - UI 结果计数
 * @property phaseIcon - 阶段图标 emoji（服务层预计算）
 * @property phaseDescription - 阶段描述文案（服务层预计算）
 */
export class ToolCallInfo {
  /** 当前阶段: '' | analyzing | executing | compiling | complete */
  phase: string = 'analyzing'
  /** 工具名称 */
  toolName: string = ''
  /** UI 摘要文本 */
  summary: string = ''
  /** UI 结果计数 */
  count: number = 0
  /** 阶段图标 emoji（服务层预计算，避免 @Builder 内调用方法） */
  phaseIcon: string = '⚡'
  /** 阶段描述文案（服务层预计算，避免 @Builder 内调用方法） */
  phaseDescription: string = 'AI 正在分析...'
}

/** 工具调用阶段信息回调。 */
export type ToolCallCallback = (info: ToolCallInfo) => void
