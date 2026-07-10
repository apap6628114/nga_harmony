/**
 * 自定义 AI 激活配置与调用门面。
 *
 * 统一封装当前激活的用户自定义 AI 配置校验、调用与错误文案，
 * 页面层不再直接处理配置索引或额外调用分支。
 * 支持联网搜索（Function Calling + Tavily）。
 */

import { appStore } from '../../store/AppStore'
import type { AiProviderProfile } from '../../model/AiConfig'
import {
  chatComplete,
  chatCompleteStream,
  chatCompleteWithTools,
  chatCompleteStreamToolDecision,
  ChatMessage
} from './OpenAiCompatibleClient'
import type {
  ChatStreamChunkCallback,
  ToolCallResult
} from './OpenAiCompatibleClient'
import { searchWeb } from './WebSearchService'
import type { SearchResponse } from './WebSearchService'
import { translateError } from './AiErrorTranslator'
import { Logger, DOMAIN_SERVICE } from '../../common/utils/Logger'

const logger = new Logger(DOMAIN_SERVICE, 'ActiveAiSvc')

/** AI 处理阶段状态回调，用于 UI 展示不同阶段的提示文案。 */
export type ChatStatusCallback = (status: string) => void

/**
 * 工具调用阶段信息，用于 UI 展示工具调用的进度与详情。
 *
 * @property phase - 当前阶段: analyzing | searching | compiling | complete
 * @property toolName - 工具名称（如 'web_search'）
 * @property query - 搜索关键词
 * @property resultCount - 搜索结果数量
 * @property phaseIcon - 阶段图标 emoji（预计算，避免 @Builder 内调用方法）
 * @property phaseDescription - 阶段描述文案（预计算，避免 @Builder 内调用方法）
 */
export class ToolCallInfo {
  /** 当前阶段: analyzing | searching | compiling | complete */
  phase: string = 'analyzing'
  /** 工具名称 */
  toolName: string = ''
  /** 搜索关键词 */
  query: string = ''
  /** 搜索结果数量 */
  resultCount: number = 0
  /** 阶段图标 emoji（由服务层预计算） */
  phaseIcon: string = '⚡'
  /** 阶段描述文案（由服务层预计算） */
  phaseDescription: string = 'AI 正在分析是否需要搜索互联网...'
}

/** 工具调用阶段信息回调。 */
export type ToolCallCallback = (info: ToolCallInfo) => void

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
 * 当配置关闭流式输出时，自动降级为普通请求并一次性回调完整文本。
 * 当启用联网搜索时，先通过 Function Calling 判断模型是否需要搜索，
 * 若需要则调用 Tavily 获取结果后再输出最终答案。
 *
 * @param messages - 对话消息列表
 * @param onDelta - 文本增量回调
 * @param onStatus - 可选的状态更新回调，用于 UI 展示不同阶段提示
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

	  // 联网搜索流程：通过 Function Calling 让模型决定是否需要搜索
		  if (profile.enableSearch && profile.tavilyApiKey.trim().length > 0) {
		    logger.info('启用联网搜索: model=%s', profile.modelName)
		    return chatCompleteWithWebSearch(profile, messages, onDelta, onStatus, onToolCall)
	  }

  // 传统流程
  if (!profile.streaming) {
    const result: string = await chatComplete(profile, messages)
    onDelta(result)
    return result
  }
  return chatCompleteStream(profile, messages, onDelta)
}

/**
 * 联网搜索对话补全流程。
 *
 * 分两阶段：
 *  1. 非流式请求带 tools 声明 → 模型返回 tool_calls（决定搜索）或
 *     直接回复（无需搜索）
 *  2. 若需搜索 → 调 Tavily → 非流式请求获取最终答案
 *
 * @param profile - AI 提供方配置
 * @param messages - 对话消息列表
 * @param onDelta - 文本增量回调
 * @param onStatus - 可选的状态更新回调
 * @returns 模型返回的完整文本
 */
async function chatCompleteWithWebSearch(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  onDelta: ChatStreamChunkCallback,
  onStatus?: ChatStatusCallback,
  onToolCall?: ToolCallCallback
): Promise<string> {
  // Step 1: 定义 web_search 工具（用纯 Record 对象，避免类序列化问题）
  const queryProp: Record<string, string> = {}
  queryProp['type'] = 'string'
  queryProp['description'] = '搜索关键词或自然语言问题'

  const props: Record<string, Object> = {}
  props['query'] = queryProp

  const params: Record<string, Object> = {}
  params['type'] = 'object'
  params['properties'] = props
  params['required'] = ['query']

  const funcDef: Record<string, Object> = {}
  funcDef['name'] = 'web_search'
  funcDef['description'] = '搜索互联网获取最新信息。当用户需要实时数据、最新新闻或训练数据之外的知识时使用此工具。'
  funcDef['parameters'] = params

  const toolDef: Record<string, Object> = {}
  toolDef['type'] = 'function'
  toolDef['function'] = funcDef

  const tools: Object[] = [toolDef]

  // Step 2: 非流式请求带 tools，让模型决定是否需要搜索
  let toolCallInfo: ToolCallInfo = new ToolCallInfo()
  toolCallInfo.phase = 'analyzing'
  toolCallInfo.toolName = 'web_search'
  toolCallInfo.phaseIcon = '⚡'
  toolCallInfo.phaseDescription = 'AI 正在分析是否需要搜索互联网...'
  onToolCall?.(toolCallInfo)
  onStatus?.('⚡ AI 正在分析是否需要搜索互联网...')

	  let toolResult: ToolCallResult
	  let phase1Streamed: boolean = false
	  try {
	    // 流式工具决策：流式输出思考 token 到 UI，同时解析 tool_calls
	    if (profile.streaming) {
	      toolResult = await chatCompleteStreamToolDecision(profile, messages, tools, onDelta)
	      phase1Streamed = true
	    } else {
	      toolResult = await chatCompleteWithTools(profile, messages, tools)
	    }
  } catch (e) {
    // 流式工具决策失败（模型不支持 function calling 或参数问题），
    // 降级为不带 tools 声明的普通请求
    const toolErr: Error = e as Error
    logger.warn('流式工具决策失败，降级为普通请求: %{public}s', toolErr.message ?? '')
    try {
      if (!profile.streaming) {
        const fallback: string = await chatComplete(profile, messages)
        onDelta(fallback)
        return fallback
      }
      return chatCompleteStream(profile, messages, onDelta)
    } catch (fallbackErr) {
      // 降级也失败，将原始错误向上传播让 formatAiCompletionError 翻译
      const fbErr: Error = fallbackErr as Error
      logger.warn('普通对话也失败: %{public}s', fbErr.message ?? '')
      throw new Error(toolErr.message || '工具调用失败')
    }
  }

  // Step 3: 模型直接给出了回答（无需搜索）
  if (!toolResult.hasToolCalls) {
    // 非流式模式下 content 未通过 onDelta 输出过，需要手动回调
    if (!phase1Streamed) {
      onDelta(toolResult.content)
    }
    return toolResult.content
  }

  // Step 4: 执行 Tavily 网络搜索
  const searchQuery: string = toolResult.toolCalls[0].function.arguments
  let parsedQuery: string = searchQuery
  try {
    const parsed: Record<string, string> = JSON.parse(searchQuery) as Record<string, string>
    parsedQuery = parsed['query'] ?? searchQuery
  } catch (e) {
    // arguments 不是标准 JSON 时直接用原始字符串
    parsedQuery = searchQuery
  }

  // 若解析出的查询为空，用用户最后一条消息作为查询
  if (parsedQuery.trim().length === 0) {
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === 'user' && messages[i].content.trim().length > 0) {
        parsedQuery = messages[i].content
        break
      }
    }
  }

  // 推送搜索阶段信息
  toolCallInfo.phase = 'searching'
  toolCallInfo.query = parsedQuery
  toolCallInfo.phaseIcon = '🌐'
  toolCallInfo.phaseDescription = '正在搜索 "' + parsedQuery + '"'
  onToolCall?.(toolCallInfo)
  onStatus?.('🔍 正在搜索互联网...')

  const searchResponse: SearchResponse = await searchWeb(parsedQuery, profile.tavilyApiKey)

  // 推送整理结果阶段信息
  toolCallInfo.phase = 'compiling'
  toolCallInfo.resultCount = searchResponse.results.length
  toolCallInfo.phaseIcon = '📝'
  toolCallInfo.phaseDescription = '正在整理 ' + toolCallInfo.resultCount.toString() + ' 条搜索结果...'
  onToolCall?.(toolCallInfo)
  onStatus?.('📝 正在整理搜索结果...')

  // Step 5: 构建第二轮请求的消息列表
  const fullMessages: ChatMessage[] = copyMessages(messages)

  // 添加 assistant 消息（含 tool_calls）
  const assistantMsg: ChatMessage = new ChatMessage('assistant', '')
  assistantMsg.toolCalls = toolResult.toolCalls
  fullMessages.push(assistantMsg)

  // 添加 tool 结果消息 —— 每个 tool_call 都需要对应的 tool 回复
  logger.info('Phase 2 toolCalls.length=%d', toolResult.toolCalls.length)
  for (let j: number = 0; j < toolResult.toolCalls.length; j++) {
    const tcId: string = toolResult.toolCalls[j].id
    const tcName: string = toolResult.toolCalls[j].function.name
    if (j === 0 && searchResponse.success) {
      // 第一个 tool_call 使用实际的搜索结果
      const searchContext: string = buildSearchContext(searchResponse)
      fullMessages.push(new ChatMessage('tool', searchContext, tcId, tcName))
    } else if (j === 0) {
      // 第一个 tool_call 搜索失败
      fullMessages.push(new ChatMessage('tool', '网络搜索失败：' + searchResponse.errorMessage,
        tcId, tcName))
    } else {
      // 多余的 tool_call，提供简短占位回复
      fullMessages.push(new ChatMessage('tool', '搜索已完成，结果已在上一条 tool 消息中提供。', tcId, tcName))
    }
  }

  // Step 6: 流式获取最终答案（优先使用流式请求，逐步输出 tokens）
  let finalText: string
  try {
    finalText = await chatCompleteStream(profile, fullMessages, onDelta)
  } catch (e) {
    // 流式请求失败（如部分模型不支持带 tool_calls 历史的流式），降级为非流式
    logger.warn('Phase 2 流式失败，降级为非流式: %{public}s', (e as Error).message ?? '')
    onStatus?.('📝 正在生成最终回答...')
    finalText = await chatComplete(profile, fullMessages)
    onDelta(finalText)
  }

  // 推送完成状态
  toolCallInfo.phase = 'complete'
  toolCallInfo.phaseIcon = '✅'
  toolCallInfo.phaseDescription = '共搜索 ' + toolCallInfo.resultCount.toString() + ' 条结果'
  onToolCall?.(toolCallInfo)

  return finalText
}

/**
 * 将 Tavily 搜索结果构造成适合模型阅读的上下文字符串。
 *
 * @param searchResponse - Tavily 搜索结果
 * @returns 带来源标记的上下文文本
 */
function buildSearchContext(searchResponse: SearchResponse): string {
  let context: string = ''

  if (searchResponse.answer.length > 0) {
    context += '搜索摘要：' + searchResponse.answer + '\n\n'
  }

  context += '搜索结果：\n'
  for (let i = 0; i < searchResponse.results.length; i++) {
    const item = searchResponse.results[i]
    context += (i + 1).toString() + '. [' + item.title + '](' + item.url + ')\n'
    if (item.content.length > 0) {
      context += '   ' + item.content + '\n'
    }
    context += '\n'
  }

  context += '请基于以上搜索结果回答用户问题，并标注引用来源。'
  return context
}

/**
 * 深拷贝 ChatMessage 数组。
 *
 * ArkTS 不支持 spread 操作符，使用循环逐项复制。
 *
 * @param messages - 原始消息数组
 * @returns 副本
 */
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
 * @returns 用户可读的错误信息
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
