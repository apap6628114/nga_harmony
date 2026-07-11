/**
 * 联网搜索工具适配器。
 *
 * 将 Web Search 封装为 Function Calling 工具，
 * 实现 ToolAdapter 接口，供 ToolRegistry 注册。
 */

import type { ToolCall } from '../OpenAiCompatibleClient'
import type { ChatMessage } from '../OpenAiCompatibleClient'
import { type ToolAdapter, ToolResult } from './ToolAdapter'
import { searchWeb, buildSearchContext, getActiveWebSearchProfile } from '../WebSearchService'

/** 联网搜索工具名称。 */
const WEB_SEARCH_TOOL_NAME: string = 'web_search'

/**
 * 联网搜索工具适配器。
 *
 * 封装搜索工具的定义、可用性检查和执行逻辑。
 */
export class WebSearchTool implements ToolAdapter {
  /**
   * 获取 OpenAI Function Calling 工具定义。
   *
   * @returns web_search 工具定义对象
   */
  getDefinition(): Object {
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
    funcDef['name'] = WEB_SEARCH_TOOL_NAME
    funcDef['description'] = '搜索互联网获取最新信息。当用户需要实时数据、最新新闻或训练数据之外的知识时使用此工具。'
    funcDef['parameters'] = params

    const toolDef: Record<string, Object> = {}
    toolDef['type'] = 'function'
    toolDef['function'] = funcDef

    return toolDef
  }

  /**
   * 判断联网搜索是否可用。
   *
   * 当用户激活了至少一个搜索提供商配置时可用。
   *
   * @returns true 表示搜索提供商已配置
   */
  isAvailable(): boolean {
    return getActiveWebSearchProfile() !== null
  }

  /**
   * 执行联网搜索。
   *
   * @param toolCall - 模型发起的 web_search 调用
   * @param messages - 当前对话消息列表
   * @returns 搜索结果
   */
  async execute(toolCall: ToolCall, messages: ChatMessage[]): Promise<ToolResult> {
    const query: string = parseSearchQuery(toolCall.function.arguments, messages)

    const response = await searchWeb(query)
    const result: ToolResult = new ToolResult()
    result.success = response.success
    result.summary = query
    result.count = response.success ? response.results.length : 0

    if (response.success && response.results.length > 0) {
      result.content = buildSearchContext(response)
    } else if (response.success) {
      result.content = '联网搜索没有找到可用结果：' + query
    } else {
      result.content = '网络搜索失败：' + response.errorMessage
      result.errorMessage = response.errorMessage
    }

    return result
  }
}

/**
 * 从 tool call 参数中解析查询文本。
 *
 * @param argumentsText - tool call function.arguments 原文（JSON 字符串）
 * @param messages - 对话消息列表
 * @returns 搜索查询文本
 */
function parseSearchQuery(argumentsText: string, messages: ChatMessage[]): string {
  let parsedQuery: string = argumentsText
  try {
    const parsedValue: Object = JSON.parse(argumentsText) as Object
    if (typeof parsedValue === 'object' && parsedValue !== null) {
      const parsedRecord: Record<string, Object> = parsedValue as Record<string, Object>
      const queryValue: Object | undefined = parsedRecord['query']
      if (typeof queryValue === 'string') {
        parsedQuery = queryValue
      }
    }
  } catch (e) {
    parsedQuery = argumentsText
  }

  if (parsedQuery.trim().length > 0) {
    return parsedQuery.trim()
  }
  return getLastUserMessage(messages)
}

/**
 * 获取最后一条用户消息作为兜底搜索词。
 *
 * @param messages - 对话消息列表
 * @returns 用户最后一条非空消息
 */
function getLastUserMessage(messages: ChatMessage[]): string {
  for (let i: number = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'user' && messages[i].content.trim().length > 0) {
      return messages[i].content.trim()
    }
  }
  return ''
}
