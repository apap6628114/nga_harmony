/**
 * 自定义 AI 激活配置与调用门面。
 *
 * 统一封装当前激活的用户自定义 AI 配置校验、调用与错误文案，
 * 页面层不再直接处理配置索引或额外调用分支。
 * 通过 Tool Registry 模式支持可扩展的 Function Calling 工具集。
 */

import { appStore } from '../../store/AppStore'
import type { AiProviderProfile } from '../../model/AiConfig'
import {
  chatComplete,
  chatCompleteStream,
  chatCompleteWithTools,
  chatCompleteStreamToolDecision,
  ChatMessage,
  ToolCall
} from './OpenAiCompatibleClient'
import type {
  ChatStreamChunkCallback,
  ToolCallResult
} from './OpenAiCompatibleClient'
import { WebSearchTool } from './tools/WebSearchTool'
import { ToolRegistry } from './tools/ToolRegistry'
import {
  type ToolAdapter,
  ToolResult,
  ToolCallInfo,
  type ToolCallCallback
} from './tools/ToolAdapter'
import { translateError } from './AiErrorTranslator'
import { Logger, DOMAIN_SERVICE } from '../../common/utils/Logger'

const logger = new Logger(DOMAIN_SERVICE, 'ActiveAiSvc')
/** 缓存已确认不支持 tools 的模型配置，避免每轮对话重复失败再降级。 */
const toolUnsupportedProfileKeys: Record<string, boolean> = {}

/** AI 处理阶段状态回调，用于 UI 展示不同阶段的提示文案。 */
export type ChatStatusCallback = (status: string) => void

/** 工具调用阶段信息回调。 */
export { ToolCallCallback }
/** 工具调用阶段信息。 */
export { ToolCallInfo }

/**
 * 创建并初始化工具注册中心。
 *
 * 在此函数中注册所有可用的 Function Calling 工具。
 * 新增工具时只需在此添加一行 register()。
 *
 * @returns 已初始化的 ToolRegistry 实例
 */
function createToolRegistry(): ToolRegistry {
  const registry: ToolRegistry = new ToolRegistry()
  registry.register(new WebSearchTool())
  return registry
}

/** 全局工具注册中心单例。 */
const toolRegistry: ToolRegistry = createToolRegistry()

/**
 * 获取当前激活的自定义 AI 配置。
 *
 * @returns 当前激活配置，若未选择或配置不存在则返回 null
 */
export function getActiveAiProfile(): AiProviderProfile | null {
  return appStore.getActiveAiProfile()
}

/**
 * 获取当前自定义 AI 配置不可用时的用户提示。
 *
 * @returns 空字符串表示配置可用，否则为用户可读的错误提示
 */
export function getActiveAiValidationMessage(): string {
  const profile: AiProviderProfile | null = getActiveAiProfile()
  if (!profile) {
    if (appStore.settings.aiProfiles.length === 0) {
      return '请先在设置中添加 AI 配置'
    }
    return '请先在设置中选择 AI 配置'
  }
  if (profile.endpoint.trim().length === 0 || profile.modelName.trim().length === 0) {
    return '请先在 AI 配置中填写服务地址和模型名称'
  }
  if (profile.apiKey.trim().length === 0) {
    return '请先在 AI 配置中填写 API 密钥'
  }
  return ''
}

/**
 * 使用当前激活的自定义 AI 配置发起对话补全。
 *
 * @param messages - 对话消息列表
 * @returns 模型返回文本
 */
export async function chatCompleteWithActiveAi(messages: ChatMessage[]): Promise<string> {
  const profile: AiProviderProfile | null = getActiveAiProfile()
  const validationMessage: string = getActiveAiValidationMessage()
  if (!profile || validationMessage.length > 0) {
    throw new Error(validationMessage.length > 0 ? validationMessage : '请先在设置中选择 AI 配置')
  }
  return chatComplete(profile, messages)
}

/**
 * 使用当前激活的自定义 AI 配置发起可流式展示的对话补全。
 *
 * 当有可用工具时，先通过 Function Calling 判断模型是否需要调用工具，
 * 若需要则执行工具后再输出最终答案。
 *
 * @param messages - 对话消息列表
 * @param onDelta - 文本增量回调
 * @param onStatus - 可选的状态更新回调
 * @param onToolCall - 可选的工具调用阶段回调
 * @returns 模型返回的完整文本
 */
export async function chatCompleteWithActiveAiStream(
  messages: ChatMessage[],
  onDelta: ChatStreamChunkCallback,
  onStatus?: ChatStatusCallback,
  onToolCall?: ToolCallCallback
): Promise<string> {
  const profile: AiProviderProfile | null = getActiveAiProfile()
  const validationMessage: string = getActiveAiValidationMessage()
  if (!profile || validationMessage.length > 0) {
    throw new Error(validationMessage.length > 0 ? validationMessage : '请先在设置中选择 AI 配置')
  }

  if (shouldTryToolCalling(profile)) {
    return tryToolCalling(profile, messages, onDelta, onStatus, onToolCall)
  }

  return chatCompleteWithoutTools(profile, messages, onDelta)
}

/**
 * 不启用工具调用时的普通对话流程。
 *
 * @param profile - AI 提供方配置
 * @param messages - 对话消息列表
 * @param onDelta - 文本增量回调
 * @returns 模型返回的完整文本
 */
async function chatCompleteWithoutTools(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  onDelta: ChatStreamChunkCallback
): Promise<string> {
  if (!profile.streaming) {
    const result: string = await chatComplete(profile, messages)
    onDelta(result)
    return result
  }
  return chatCompleteStream(profile, messages, onDelta)
}

/**
 * 判断当前是否应尝试工具调用。
 *
 * 条件：有可用工具且当前 AI 模型未被标记为不支持 tools。
 *
 * @param profile - AI 提供方配置
 * @returns true 表示应尝试工具调用
 */
function shouldTryToolCalling(profile: AiProviderProfile): boolean {
  return toolRegistry.getAvailableAdapters().length > 0 &&
    !isToolUnsupported(profile)
}

/**
 * 通用工具调用对话流程。
 *
 * 分三阶段：
 * 1. 请求带 tools 声明，让模型决定需要调用哪些工具。
 * 2. 执行模型请求的工具，收集结果。
 * 3. 将工具结果注入对话，请求模型生成最终答案。
 *
 * @param profile - AI 提供方配置
 * @param messages - 对话消息列表
 * @param onDelta - 文本增量回调
 * @param onStatus - 可选的状态更新回调
 * @param onToolCall - 可选的工具调用阶段回调
 * @returns 模型返回的完整文本
 */
async function tryToolCalling(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  onDelta: ChatStreamChunkCallback,
  onStatus?: ChatStatusCallback,
  onToolCall?: ToolCallCallback
): Promise<string> {
  const tools: Object[] = toolRegistry.getToolDefinitions()

  // Phase 1: 工具决策
  const toolCallInfo: ToolCallInfo = createToolInfo('analyzing', '⚡', 'AI 正在分析...', '', 0)
  onToolCall?.(toolCallInfo)
  onStatus?.('⚡ AI 正在分析...')

  let toolResult: ToolCallResult
  let decisionText: string = ''
  try {
    if (profile.streaming) {
      toolResult = await chatCompleteStreamToolDecision(profile, messages, tools, (chunk: string): void => {
        decisionText += chunk
      })
    } else {
      toolResult = await chatCompleteWithTools(profile, messages, tools)
      decisionText = toolResult.content
    }
  } catch (e) {
    const toolErr: Error = e as Error
    if (shouldCacheToolFailure(toolErr)) {
      markToolUnsupported(profile)
    }
    logger.warn('工具决策失败，降级为普通请求: %{public}s', toolErr.message ?? '')
    notifyNoToolCall(onToolCall)
    onStatus?.('AI 正在生成回答...')
    try {
      return await chatCompleteWithoutTools(profile, messages, onDelta)
    } catch (fallbackErr) {
      const fbErr: Error = fallbackErr as Error
      logger.warn('普通对话也失败: %{public}s', fbErr.message ?? '')
      throw new Error(toolErr.message || '工具调用失败')
    }
  }

  if (!toolResult.hasToolCalls) {
    const directText: string = toolResult.content.length > 0 ? toolResult.content : decisionText
    notifyNoToolCall(onToolCall)
    if (directText.length > 0) {
      onDelta(directText)
    }
    return directText
  }

  // Phase 2: 执行工具
  const results: ToolResult[] = await executeToolCalls(
    toolResult.toolCalls,
    messages,
    toolCallInfo,
    onStatus,
    onToolCall
  )
  const totalCount: number = countToolResults(results)
  const combinedSummary: string = buildCombinedSummary(results)

  toolCallInfo.phase = 'compiling'
  toolCallInfo.summary = combinedSummary
  toolCallInfo.count = totalCount
  toolCallInfo.phaseIcon = '📝'
  toolCallInfo.phaseDescription = '正在整理 ' + totalCount.toString() + ' 条结果...'
  onToolCall?.(toolCallInfo)
  onStatus?.('📝 正在整理结果...')

  if (!hasSuccessfulResult(results)) {
    const failedText: string = buildToolFailedAnswer(results)
    completeToolCall(toolCallInfo, '工具执行失败', onToolCall)
    onDelta(failedText)
    return failedText
  }

  if (totalCount === 0) {
    const emptyText: string = buildToolEmptyAnswer()
    completeToolCall(toolCallInfo, '未找到可用结果', onToolCall)
    onDelta(emptyText)
    return emptyText
  }

  // Phase 3: 最终回答
  const fullMessages: ChatMessage[] = buildMessagesWithToolResults(messages, toolResult, results)
  const finalText: string = await completeFinalAnswer(profile, fullMessages, onDelta, onStatus)
  completeToolCall(toolCallInfo, '共 ' + totalCount.toString() + ' 条结果', onToolCall)
  return finalText
}

/**
 * 顺序执行模型请求的所有工具调用。
 *
 * @param toolCalls - 模型发起的工具调用列表
 * @param messages - 对话消息列表
 * @param toolCallInfo - 可复用的工具状态对象
 * @param onStatus - 可选的状态更新回调
 * @param onToolCall - 可选的工具调用阶段回调
 * @returns 工具执行结果列表
 */
async function executeToolCalls(
  toolCalls: ToolCall[],
  messages: ChatMessage[],
  toolCallInfo: ToolCallInfo,
  onStatus?: ChatStatusCallback,
  onToolCall?: ToolCallCallback
): Promise<ToolResult[]> {
  const results: ToolResult[] = []
  for (let i: number = 0; i < toolCalls.length; i++) {
    const toolCall: ToolCall = toolCalls[i]
    const adapter: ToolAdapter | null = toolRegistry.getAdapter(toolCall.function.name)

    toolCallInfo.phase = 'executing'
    toolCallInfo.toolName = toolCall.function.name
    toolCallInfo.phaseIcon = '🔧'
    toolCallInfo.phaseDescription = '正在执行 ' + toolCall.function.name + '...'
    onToolCall?.(toolCallInfo)
    onStatus?.('🔧 正在执行工具调用...')

    if (!adapter) {
      const error: ToolResult = new ToolResult()
      error.errorMessage = '未找到工具适配器: ' + toolCall.function.name
      error.content = '工具执行失败：未找到 ' + toolCall.function.name
      results.push(error)
      continue
    }

    const result: ToolResult = await adapter.execute(toolCall, messages)
    // 更新工具特定的 UI 信息
    if (result.summary.length > 0) {
      toolCallInfo.summary = result.summary
      toolCallInfo.phaseDescription = '正在执行: ' + result.summary
      onToolCall?.(toolCallInfo)
    }
    results.push(result)
  }
  return results
}

/**
 * 构造包含工具调用结果的二阶段消息。
 *
 * @param messages - 原始对话消息
 * @param toolResult - 模型工具决策结果
 * @param results - 工具执行结果列表
 * @returns 二阶段补全消息
 */
function buildMessagesWithToolResults(
  messages: ChatMessage[],
  toolResult: ToolCallResult,
  results: ToolResult[]
): ChatMessage[] {
  const fullMessages: ChatMessage[] = copyMessages(messages)
  const assistantMsg: ChatMessage = new ChatMessage('assistant', '')
  assistantMsg.toolCalls = toolResult.toolCalls
  fullMessages.push(assistantMsg)

  for (let i: number = 0; i < results.length; i++) {
    const tc: ToolCall = toolResult.toolCalls[i]
    const tcId: string = tc.id
    const tcName: string = tc.function.name
    fullMessages.push(new ChatMessage('tool', results[i].content, tcId, tcName))
  }
  return fullMessages
}

/**
 * 获取最终模型回答。
 *
 * @param profile - AI 提供方配置
 * @param fullMessages - 包含工具结果的消息列表
 * @param onDelta - 文本增量回调
 * @param onStatus - 可选的状态更新回调
 * @returns 最终回答文本
 */
async function completeFinalAnswer(
  profile: AiProviderProfile,
  fullMessages: ChatMessage[],
  onDelta: ChatStreamChunkCallback,
  onStatus?: ChatStatusCallback
): Promise<string> {
  try {
    return await chatCompleteStream(profile, fullMessages, onDelta)
  } catch (e) {
    logger.warn('Phase 3 流式失败，降级为非流式: %{public}s', (e as Error).message ?? '')
    onStatus?.('📝 正在生成最终回答...')
    const finalText: string = await chatComplete(profile, fullMessages)
    onDelta(finalText)
    return finalText
  }
}

// ============================================================
// UI 状态辅助
// ============================================================

/**
 * 创建工具阶段状态对象。
 *
 * @param phase - 阶段值
 * @param icon - 阶段图标
 * @param description - 阶段描述
 * @param summary - 工具摘要
 * @param count - 结果计数
 * @returns 工具阶段状态
 */
function createToolInfo(
  phase: string,
  icon: string,
  description: string,
  summary: string,
  count: number
): ToolCallInfo {
  const info: ToolCallInfo = new ToolCallInfo()
  info.phase = phase
  info.phaseIcon = icon
  info.phaseDescription = description
  info.summary = summary
  info.count = count
  return info
}

/** 通知页面当前没有工具调用。 */
function notifyNoToolCall(onToolCall?: ToolCallCallback): void {
  onToolCall?.(createToolInfo('', '', '', '', 0))
}

/** 标记工具调用完成。 */
function completeToolCall(info: ToolCallInfo, description: string, onToolCall?: ToolCallCallback): void {
  info.phase = 'complete'
  info.phaseIcon = '✅'
  info.phaseDescription = description
  onToolCall?.(info)
}

// ============================================================
// 结果统计
// ============================================================

/** 统计工具结果总数。 */
function countToolResults(results: ToolResult[]): number {
  let total: number = 0
  for (let i: number = 0; i < results.length; i++) {
    total += results[i].count
  }
  return total
}

/** 判断是否至少有一次工具执行成功。 */
function hasSuccessfulResult(results: ToolResult[]): boolean {
  for (let i: number = 0; i < results.length; i++) {
    if (results[i].success) {
      return true
    }
  }
  return false
}

/** 拼接多次工具调用摘要。 */
function buildCombinedSummary(results: ToolResult[]): string {
  let combined: string = ''
  for (let i: number = 0; i < results.length; i++) {
    if (results[i].summary.length === 0) {
      continue
    }
    if (combined.length > 0) {
      combined += '；'
    }
    combined += results[i].summary
  }
  return combined
}

// ============================================================
// 错误消息构造
// ============================================================

/** 构造全部工具执行失败时的回答。 */
function buildToolFailedAnswer(results: ToolResult[]): string {
  let reason: string = '未知错误'
  for (let i: number = 0; i < results.length; i++) {
    if (!results[i].success && results[i].errorMessage.length > 0) {
      reason = results[i].errorMessage
      break
    }
  }
  return '工具执行失败：' + reason + '\n\n我没有获取到可用的结果，因此不会基于未确认的信息继续推断。请稍后重试或换一种方式提问。'
}

/** 构造工具执行成功但无结果时的回答。 */
function buildToolEmptyAnswer(): string {
  return '工具执行完成但没有找到可用结果。\n\n我没有足够的来源回答这个问题。可以换一个更具体的关键词重试。'
}

// ============================================================
// tools 支持缓存
// ============================================================

/** 判断工具调用失败是否应缓存为不支持 tools。 */
function shouldCacheToolFailure(error: Error): boolean {
  const statusCode: number = parseInt(error.message)
  if (statusCode === 400 || statusCode === 404 || statusCode === 422 || statusCode === 501) {
    return true
  }
  const msg: string = error.message.toLowerCase()
  return msg.indexOf('tool') >= 0 || msg.indexOf('function') >= 0
}

/** 标记当前配置不支持工具调用。 */
function markToolUnsupported(profile: AiProviderProfile): void {
  toolUnsupportedProfileKeys[getToolCapabilityKey(profile)] = true
}

/** 判断当前配置是否已被标记为不支持工具调用。 */
function isToolUnsupported(profile: AiProviderProfile): boolean {
  return toolUnsupportedProfileKeys[getToolCapabilityKey(profile)] === true
}

/** 构造工具能力缓存键。 */
function getToolCapabilityKey(profile: AiProviderProfile): string {
  return profile.endpoint.trim() + '\n' + profile.modelName.trim()
}

// ============================================================
// 工具函数
// ============================================================

/** 深拷贝 ChatMessage 数组。 */
function copyMessages(messages: ChatMessage[]): ChatMessage[] {
  const result: ChatMessage[] = []
  for (let i = 0; i < messages.length; i++) {
    const src: ChatMessage = messages[i]
    const dest: ChatMessage = new ChatMessage(src.role, src.content, src.toolCallId, src.name)
    if (src.toolCalls) {
      dest.toolCalls = src.toolCalls
    }
    result.push(dest)
  }
  return result
}

/**
 * 将 AI 调用异常转换为页面展示文案。
 *
 * @param err - 调用异常
 * @returns 用户可读错误信息
 */
export function formatAiCompletionError(err: Error): string {
  const code: number = parseInt(err.message)
  if (!isNaN(code)) {
    const info = translateError(code, err.message)
    return info.userMessage + '\n' + info.suggestion
  }
  if (err.message.length > 0 && err.message.indexOf('请先') === 0) {
    return err.message
  }
  return 'AI 调用失败：' + (err.message || '未知错误')
}
