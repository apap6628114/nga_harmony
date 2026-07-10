/**
 * OpenAI 兼容 API 客户端。
 *
 * 支持向 OpenAI 兼容端点发送对话补全请求，
 * 提供测试连接、获取模型列表功能。
 */

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Logger, DOMAIN_SERVICE } from '../../common/utils/Logger'
import type { AiProviderProfile } from '../../model/AiConfig'
import { AiTestResult } from '../../model/AiConfig'

const logger = new Logger(DOMAIN_SERVICE, 'OpenAiClient')

/** 请求超时毫秒数 */
const REQUEST_TIMEOUT: number = 60000
/** 连接超时毫秒数 */
const CONNECT_TIMEOUT: number = 15000

/** 流式响应文本增量回调 */
export type ChatStreamChunkCallback = (chunk: string) => void

/** 工具调用的函数信息。 */
export class ToolCallFunction {
  /** 函数名称 */
  name: string = ''
  /** JSON 格式参数 */
  arguments: string = ''
}

/** 工具调用（响应中模型请求调用某个工具）。 */
export class ToolCall {
  /** 工具调用 ID */
  id: string = ''
  /** 工具类型，目前固定为 'function' */
  type: string = 'function'
  /** 函数调用信息 */
  function: ToolCallFunction = new ToolCallFunction()
}

/** 工具定义的函数信息。 */
export class ToolFunctionDef {
  /** 函数名称 */
  name: string = ''
  /** 函数描述 */
  description: string = ''
  /** 参数 JSON Schema */
  parameters: Record<string, Object> = {}
}

/** 工具定义（请求中声明可供模型调用的工具）。 */
export class ToolDefinition {
  /** 工具类型 */
  type: string = 'function'
  /** 函数定义 */
  function: ToolFunctionDef = new ToolFunctionDef()

  /**
   * 创建工具定义。
   *
   * @param name - 函数名称
   * @param description - 函数描述
   * @param parameters - 参数 JSON Schema
   */
  constructor(name: string, description: string, parameters: Record<string, Object>) {
    this.function = new ToolFunctionDef()
    this.function.name = name
    this.function.description = description
    this.function.parameters = parameters
  }
}

/** chatCompleteWithTools 的返回结果。 */
export class ToolCallResult {
  /** 模型返回的文本内容（未触发工具调用时） */
  content: string = ''
  /** 模型发起的工具调用列表 */
  toolCalls: ToolCall[] = []
  /** 是否有工具需要执行 */
  hasToolCalls: boolean = false
}

/** 对话消息 */
export class ChatMessage {
  /** 消息角色（user / assistant / system / tool） */
  role: string
  /** 消息内容（工具调用响应中 content 可为空字符串） */
  content: string
  /** 模型发起的工具调用列表（仅 assistant 角色） */
  toolCalls?: ToolCall[]
  /** 工具调用 ID（仅 tool 角色） */
  toolCallId?: string
  /** 工具名称（仅 tool 角色） */
  name?: string

  /**
   * 创建对话消息。
   *
   * @param role - 消息角色
   * @param content - 消息内容
   * @param toolCallId - 工具调用 ID（tool 角色时传入）
   * @param name - 工具名称（tool 角色时传入）
   */
  constructor(role: string, content: string, toolCallId?: string, name?: string) {
    this.role = role
    this.content = content
    this.toolCallId = toolCallId
    this.name = name
  }
}

/** 流式响应解析状态。 */
class ChatStreamParser {
  /** 尚未解析成完整 SSE 事件的文本。 */
  private pendingText: string = ''
  /** 已解析出的完整助手回复文本。 */
  private content: string = ''
  /** 累积的流式 tool_calls（按 index 索引）。 */
  private accumulatedToolCalls: Record<string, Object>[] = []
  /** 最终 finish_reason。 */
  private finishReason: string = ''

  /**
   * 追加一段响应文本并解析其中完整的 SSE 事件。
   *
   * @param text - 新收到的 UTF-8 文本
   * @param onDelta - 文本增量回调
   */
  append(text: string, onDelta: ChatStreamChunkCallback): void {
    this.pendingText += text
    this.pendingText = this.pendingText.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
    this.parseAvailableEvents(onDelta)
  }

  /**
   * 结束解析并处理剩余缓冲。
   *
   * @param onDelta - 文本增量回调
   * @returns 完整助手回复文本
   */
  finish(onDelta: ChatStreamChunkCallback): string {
    if (this.pendingText.trim().length > 0) {
      this.parseEvent(this.pendingText, onDelta)
      this.pendingText = ''
    }
    return this.content
  }

  /**
   * 获取解析到的 finish_reason。
   *
   * @returns finish_reason 值（如 'stop', 'tool_calls'），无则返回空字符串
   */
  getFinishReason(): string {
    return this.finishReason
  }

  /**
   * 将累积的流式 tool_calls 转换为 ToolCall 数组。
   *
   * @returns 工具调用列表
   */
  getToolCalls(): ToolCall[] {
    const result: ToolCall[] = []
    for (let i: number = 0; i < this.accumulatedToolCalls.length; i++) {
      const raw: Record<string, Object> = this.accumulatedToolCalls[i]
      if ((raw['id'] as string ?? '') === '') {
        continue
      }
      const tc: ToolCall = new ToolCall()
      tc.id = (raw['id'] as string) ?? ''
      tc.type = (raw['type'] as string) ?? 'function'
      const func: Record<string, Object> = raw['function'] as Record<string, Object>
      if (func) {
        tc.function.name = (func['name'] as string) ?? ''
        tc.function.arguments = (func['arguments'] as string) ?? ''
      }
      result.push(tc)
    }
    return result
  }

  /**
   * 循环解析当前缓冲中完整的 SSE 事件。
   *
   * @param onDelta - 文本增量回调
   */
  private parseAvailableEvents(onDelta: ChatStreamChunkCallback): void {
    let separatorIndex: number = this.pendingText.indexOf('\n\n')
    while (separatorIndex >= 0) {
      const eventText: string = this.pendingText.substring(0, separatorIndex)
      this.pendingText = this.pendingText.substring(separatorIndex + 2)
      this.parseEvent(eventText, onDelta)
      separatorIndex = this.pendingText.indexOf('\n\n')
    }
  }

  /**
   * 解析单个 SSE 事件。
   *
   * @param eventText - SSE 事件文本
   * @param onDelta - 文本增量回调
   */
  private parseEvent(eventText: string, onDelta: ChatStreamChunkCallback): void {
    const lines: string[] = eventText.split('\n')
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i].trim()
      if (!line.startsWith('data:')) {
        continue
      }
      const dataText: string = line.substring(5).trim()
      if (dataText.length === 0) {
        continue
      }
      if (dataText === '[DONE]') {
        continue
      }
      // 提取文本增量
      const delta: string = parseStreamDelta(dataText)
      if (delta.length > 0) {
        this.content += delta
        onDelta(delta)
      }
      // 提取 finish_reason 和 tool_calls（用于流式工具决策）
      this.extractStreamMeta(dataText)
    }
  }

  /**
   * 从流式 chunk JSON 中提取 finish_reason 和 tool_calls delta。
   *
   * @param dataText - SSE data JSON 字符串
   */
  private extractStreamMeta(dataText: string): void {
    try {
      const json: Record<string, Object> = JSON.parse(dataText) as Record<string, Object>
      const choices: Object[] = json['choices'] as Object[]
      if (!choices || choices.length === 0) {
        return
      }
      const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>

      // 提取 finish_reason
      if (firstChoice['finish_reason'] !== undefined && firstChoice['finish_reason'] !== null) {
        this.finishReason = firstChoice['finish_reason'] as string
      }

      // 提取 tool_calls delta
      const delta: Record<string, Object> = firstChoice['delta'] as Record<string, Object>
      if (delta && delta['tool_calls'] !== undefined) {
        this.accumulateToolCallDelta(delta)
      }
    } catch (e) {
      // 解析失败静默跳过，parseStreamDelta 已有日志
    }
  }

  /**
   * 将流式 tool_calls delta 累积到 accumulatedToolCalls。
   *
   * 每个 delta.tool_calls 元素按 index 合并：
   * - id/type/function.name 只在首个 chunk 出现
   * - function.arguments 是增量拼接的
   *
   * @param delta - choices[0].delta 对象
   */
  private accumulateToolCallDelta(delta: Record<string, Object>): void {
    const toolCallDeltas: Object[] = delta['tool_calls'] as Object[]
    if (!toolCallDeltas || toolCallDeltas.length === 0) {
      return
    }
    for (let i: number = 0; i < toolCallDeltas.length; i++) {
      const chunkDelta: Record<string, Object> = toolCallDeltas[i] as Record<string, Object>
      const idx: number = (chunkDelta['index'] as number) ?? this.accumulatedToolCalls.length

      // 确保 accumulator 数组有足够空间
      while (this.accumulatedToolCalls.length <= idx) {
        const empty: Record<string, Object> = {}
        this.accumulatedToolCalls.push(empty)
      }

      const acc: Record<string, Object> = this.accumulatedToolCalls[idx]

      // 合并顶层字段
      if (chunkDelta['id'] !== undefined) {
        acc['id'] = chunkDelta['id']
      }
      if (chunkDelta['type'] !== undefined) {
        acc['type'] = chunkDelta['type']
      }

      // 合并 function 字段（增量拼接 arguments）
      if (chunkDelta['function'] !== undefined) {
        const funcDelta: Record<string, Object> = chunkDelta['function'] as Record<string, Object>
        if (!acc['function']) {
          const emptyFunc: Record<string, Object> = {}
          emptyFunc['name'] = ''
          emptyFunc['arguments'] = ''
          acc['function'] = emptyFunc
        }
        const accFunc: Record<string, Object> = acc['function'] as Record<string, Object>
        if (funcDelta['name'] !== undefined) {
          accFunc['name'] = funcDelta['name']
        }
        if (funcDelta['arguments'] !== undefined) {
          accFunc['arguments'] = (accFunc['arguments'] as string ?? '') + (funcDelta['arguments'] as string ?? '')
        }
      }
    }
  }
}

/**
 * 向 OpenAI 兼容端点发送聊天补全请求。
 *
 * @param profile - AI 提供方配置
 * @param messages - 消息列表
 * @returns 模型返回的完整文本
 */
export async function chatComplete(
  profile: AiProviderProfile,
  messages: ChatMessage[]
): Promise<string> {
  const url: string = buildChatUrl(profile.endpoint)
  const body: string = buildRequestBody(profile, messages, false)

  const httpRequest: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: buildHeaders(profile.apiKey),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: REQUEST_TIMEOUT,
      connectTimeout: CONNECT_TIMEOUT
    })

	    const statusCode: number = response.responseCode
	    const responseText: string = (response.result as string) ?? ''
	
	    if (statusCode !== 200) {
	      logger.warn('chatComplete failed: HTTP %d, body: %{public}s', statusCode, responseText.substring(0, 300))
	      throw new Error(String(statusCode))
	    }
	
	    const content: string = parseChatResponse(responseText)
	    if (content.length === 0) {
	      throw new Error('AI 响应为空或格式不兼容')
	    }
		    return content
		  } finally {
		    httpRequest.destroy()
		  }
		}
		
		/**
		 * 向 OpenAI 兼容端点发送流式聊天补全请求，携带工具声明并实时解析工具决策。
		 *
		 * 与 chatCompleteWithTools 不同，此函数使用 streaming=true，
		 * 在流式过程中实时输出文本增量（推理 token）到 onDelta，
		 * 同时在解析到 tool_calls 或 stop 时自动完成工具决策提取。
		 *
		 * @param profile - AI 提供方配置
		 * @param messages - 消息列表
		 * @param tools - 工具定义列表
		 * @param onDelta - 文本增量回调
		 * @returns 包含文本回复或工具调用的结果
		 */
		export async function chatCompleteStreamToolDecision(
		  profile: AiProviderProfile,
		  messages: ChatMessage[],
		  tools: Object[],
		  onDelta: ChatStreamChunkCallback
		): Promise<ToolCallResult> {
		  const url: string = buildChatUrl(profile.endpoint)
		  const body: string = buildRequestBody(profile, messages, true, tools)
		  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
		  const parser: ChatStreamParser = new ChatStreamParser()
		  const httpRequest: http.HttpRequest = http.createHttp()
		
		  return new Promise<ToolCallResult>((resolve: (value: ToolCallResult) => void, reject: (reason: Error) => void): void => {
		    let settled: boolean = false
		    let streamError: Error | null = null
		
		    const cleanup = (): void => {
		      httpRequest.off('dataReceive', dataReceiveCallback)
		      httpRequest.off('dataEnd', dataEndCallback)
		      httpRequest.destroy()
		    }
		
		    const rejectOnce = (error: Error): void => {
		      if (settled) {
		        return
		      }
		      settled = true
		      cleanup()
		      reject(error)
		    }
		
		    const resolveOnce = (result: ToolCallResult): void => {
		      if (settled) {
		        return
		      }
		      settled = true
		      cleanup()
		      resolve(result)
		    }
		
		    const dataReceiveCallback = (data: ArrayBuffer): void => {
		      try {
		        const decodedText: string | undefined = decoder.decodeWithStream(new Uint8Array(data), { stream: true })
		        const text: string = decodedText ?? ''
		        if (text.length === 0) {
		          return
		        }
		        parser.append(text, onDelta)
		      } catch (err) {
		        const e: Error = err as Error
		        streamError = new Error(e.message || 'AI 流式响应解析失败')
		      }
		    }
		
		    const dataEndCallback = (): void => {
		      try {
		        if (streamError) {
		          rejectOnce(streamError)
		          return
		        }
		        const decodedTail: string | undefined = decoder.decodeWithStream(new Uint8Array(new ArrayBuffer(0)), {
		          stream: false
		        })
		        const tail: string = decodedTail ?? ''
		        if (tail.length > 0) {
		          parser.append(tail, onDelta)
		        }
		        const _: string = parser.finish(onDelta)
		        const finishReason: string = parser.getFinishReason()
		        const toolCalls: ToolCall[] = parser.getToolCalls()
		
		        // 构造结果
		        const result: ToolCallResult = new ToolCallResult()
		        result.content = _
		        result.toolCalls = toolCalls
		        result.hasToolCalls = toolCalls.length > 0 && finishReason === 'tool_calls'
		
		        if (!result.hasToolCalls && _.length === 0 && finishReason === 'tool_calls') {
		          rejectOnce(new Error('AI 流式响应为空或格式不兼容'))
		          return
		        }
		        resolveOnce(result)
		      } catch (err) {
		        const e: Error = err as Error
		        rejectOnce(new Error(e.message || 'AI 流式响应解析失败'))
		      }
		    }
		
		    httpRequest.on('dataReceive', dataReceiveCallback)
		    httpRequest.on('dataEnd', dataEndCallback)
		    httpRequest.requestInStream(url, {
		      method: http.RequestMethod.POST,
		      header: buildHeaders(profile.apiKey),
		      extraData: body,
		      readTimeout: REQUEST_TIMEOUT,
		      connectTimeout: CONNECT_TIMEOUT
		    }).then((statusCode: number): void => {
		      if (statusCode !== 200) {
		        logger.warn('chatCompleteStreamToolDecision failed: HTTP %d', statusCode)
		        rejectOnce(new Error(String(statusCode)))
		      }
		    }).catch((err: Error): void => {
		      logger.warn('chatCompleteStreamToolDecision request error: %{public}s', err.message ?? '')
		      rejectOnce(err)
		    })
		  })
		}
		
		/**
		 * 向 OpenAI 兼容端点发送带工具声明的聊天补全请求（非流式）。
 *
 * 模型可能选择调用工具而非直接回复文本，调用方需检查
 * result.hasToolCalls 判断是否需要执行工具调用并继续对话。
 *
 * @param profile - AI 提供方配置
 * @param messages - 消息列表
 * @param tools - 工具定义列表
 * @returns 包含文本回复或工具调用的结果
 */
export async function chatCompleteWithTools(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  tools: Object[]
): Promise<ToolCallResult> {
  const url: string = buildChatUrl(profile.endpoint)
  const body: string = buildRequestBody(profile, messages, false, tools)
  if (logger.isVerbose()) {
    logger.verbose('chatCompleteWithTools body(model=%s): %{public}s', profile.modelName, body.substring(0, 800))
  }

  const httpRequest: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: buildHeaders(profile.apiKey),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: REQUEST_TIMEOUT,
      connectTimeout: CONNECT_TIMEOUT
    })

    const statusCode: number = response.responseCode
    const responseText: string = (response.result as string) ?? ''

    if (statusCode !== 200) {
      logger.warn('chatCompleteWithTools failed: HTTP %d, body: %{public}s', statusCode, responseText.substring(0, 300))
      throw new Error(String(statusCode))
    }

    return parseToolCallResponse(responseText)
  } finally {
    httpRequest.destroy()
  }
}

/**
 * 向 OpenAI 兼容端点发送流式聊天补全请求。
 *
 * @param profile - AI 提供方配置
 * @param messages - 消息列表
 * @param onDelta - 每次收到文本增量时触发的回调
 * @returns 模型返回的完整文本
 */
export async function chatCompleteStream(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  onDelta: ChatStreamChunkCallback
): Promise<string> {
  const url: string = buildChatUrl(profile.endpoint)
  const body: string = buildRequestBody(profile, messages, true)
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
  const parser: ChatStreamParser = new ChatStreamParser()
  const httpRequest: http.HttpRequest = http.createHttp()

  return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void): void => {
    let settled: boolean = false
    let streamError: Error | null = null

    const cleanup = (): void => {
      httpRequest.off('dataReceive', dataReceiveCallback)
      httpRequest.off('dataEnd', dataEndCallback)
      httpRequest.destroy()
    }

    const rejectOnce = (error: Error): void => {
      if (settled) {
        return
      }
      settled = true
      cleanup()
      reject(error)
    }

    const resolveOnce = (content: string): void => {
      if (settled) {
        return
      }
      settled = true
      cleanup()
      resolve(content)
    }

    const dataReceiveCallback = (data: ArrayBuffer): void => {
      try {
        const decodedText: string | undefined = decoder.decodeWithStream(new Uint8Array(data), { stream: true })
        const text: string = decodedText ?? ''
        if (text.length === 0) {
          return
        }
        parser.append(text, onDelta)
      } catch (err) {
        const e: Error = err as Error
        streamError = new Error(e.message || 'AI 流式响应解析失败')
      }
    }

    const dataEndCallback = (): void => {
      try {
        if (streamError) {
          rejectOnce(streamError)
          return
        }
        const decodedTail: string | undefined = decoder.decodeWithStream(new Uint8Array(new ArrayBuffer(0)), {
          stream: false
        })
        const tail: string = decodedTail ?? ''
        if (tail.length > 0) {
          parser.append(tail, onDelta)
        }
        const content: string = parser.finish(onDelta)
        if (content.length === 0) {
          rejectOnce(new Error('AI 流式响应为空或格式不兼容'))
          return
        }
        resolveOnce(content)
      } catch (err) {
        const e: Error = err as Error
        rejectOnce(new Error(e.message || 'AI 流式响应解析失败'))
      }
    }

	    httpRequest.on('dataReceive', dataReceiveCallback)
	    httpRequest.on('dataEnd', dataEndCallback)
	    httpRequest.requestInStream(url, {
	      method: http.RequestMethod.POST,
	      header: buildHeaders(profile.apiKey),
	      extraData: body,
	      readTimeout: REQUEST_TIMEOUT,
	      connectTimeout: CONNECT_TIMEOUT
	    }).then((statusCode: number): void => {
	      if (statusCode !== 200) {
	        logger.warn('chatCompleteStream failed: HTTP %d', statusCode)
	        rejectOnce(new Error(String(statusCode)))
	      }
	    }).catch((err: Error): void => {
	      logger.warn('chatCompleteStream request error: %{public}s', err.message ?? '')
	      rejectOnce(err)
	    })
  })
}

/**
 * 测试与 AI 端点的连接。
 *
 * 发送简短测试消息验证端点可达性、API Key 有效性和模型可用性。
 *
 * @param profile - AI 提供方配置
 * @returns 测试结果
 */
export async function testConnection(profile: AiProviderProfile): Promise<AiTestResult> {
  const url: string = buildChatUrl(profile.endpoint)
  const testMessages: ChatMessage[] = [
    new ChatMessage('user', '请用一句简短的中文确认连接成功。')
  ]
  const body: string = buildRequestBody(profile, testMessages, false)

  const result: AiTestResult = new AiTestResult()

  const httpRequest: http.HttpRequest = http.createHttp()
  const startTime: number = Date.now()
  try {
    const response: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: buildHeaders(profile.apiKey),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: 15000,
      connectTimeout: 10000
    })

    result.durationMs = Date.now() - startTime

    const statusCode: number = response.responseCode
    const responseText: string = (response.result as string) ?? ''

    if (statusCode === 200) {
      result.success = true
      result.message = parseChatResponse(responseText)
    } else {
      result.success = false
      result.errorMessage = `HTTP ${statusCode}`
    }
  } catch (err) {
    result.success = false
    result.durationMs = Date.now() - startTime
    const e: Error = err as Error
    result.errorMessage = e.message || '连接失败'
  } finally {
    httpRequest.destroy()
  }
  return result
}

/**
 * 从端点获取可用模型列表。
 *
 * @param profile - AI 提供方配置
 * @returns 模型名称列表
 */
export async function listModels(profile: AiProviderProfile): Promise<string[]> {
  let baseUrl: string = profile.endpoint
    .replace(/\/chat\/completions\/?$/, '')
    .replace(/\/+$/, '')
  const url: string = baseUrl + '/models'

  const httpRequest: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: buildHeaders(profile.apiKey),
      expectDataType: http.HttpDataType.STRING,
      readTimeout: 15000,
      connectTimeout: 10000
    })

    const statusCode: number = response.responseCode
    const responseText: string = (response.result as string) ?? ''

    if (statusCode !== 200) {
      logger.error('listModels failed: HTTP %{public}d', statusCode)
      return []
    }

    return parseModelList(responseText)
  } finally {
    httpRequest.destroy()
  }
}

/**
 * 构造聊天补全请求 URL。
 *
 * @param endpoint - 用户配置的端点地址
 * @returns 完整的 /chat/completions URL
 */
function buildChatUrl(endpoint: string): string {
  let url: string = endpoint.replace(/\/+$/, '')
  if (!url.endsWith('/chat/completions')) {
    url = url + '/chat/completions'
  }
  return url
}

/**
 * 构造请求头。
 *
 * @param apiKey - API 密钥
 * @returns HTTP 请求头对象
 */
function buildHeaders(apiKey: string): Record<string, string> {
  const headers: Record<string, string> = {}
  headers['Content-Type'] = 'application/json'
  headers['Accept'] = 'text/event-stream'
  headers['Authorization'] = 'Bearer ' + apiKey
  return headers
}

/**
 * 构造请求体 JSON 字符串。
 *
 * @param profile - AI 提供方配置
 * @param messages - 消息列表
 * @param stream - 是否流式
 * @param tools - 可选的工具定义列表（纯对象数组，由调用方构建）
 * @returns JSON 字符串
 */
function buildRequestBody(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  stream: boolean,
  tools?: Object[]
): string {
  const bodyObj: Record<string, Object> = {}
  bodyObj['model'] = profile.modelName
  bodyObj['stream'] = stream
  bodyObj['temperature'] = profile.temperature
  bodyObj['max_tokens'] = profile.maxTokens

  // 序列化消息，处理工具调用相关字段
  const serializedMessages: Object[] = []
  for (let i = 0; i < messages.length; i++) {
    const msg: ChatMessage = messages[i]
    const msgObj: Record<string, Object | null> = {}
    msgObj['role'] = msg.role

	    if (msg.role === 'assistant' && msg.toolCalls && msg.toolCalls.length > 0) {
	      // assistant 消息带 tool_calls 时 content 为 null
	      msgObj['content'] = null
	      const toolCallsJson: Object[] = []
	      for (let j = 0; j < msg.toolCalls.length; j++) {
	        const tc: ToolCall = msg.toolCalls[j]
	        const tcObj: Record<string, Object> = {}
	        tcObj['id'] = tc.id
	        tcObj['type'] = tc.type
	        const funcObj: Record<string, string> = {}
	        funcObj['name'] = tc.function.name
	        funcObj['arguments'] = tc.function.arguments
	        tcObj['function'] = funcObj
	        toolCallsJson.push(tcObj)
	      }
	      msgObj['tool_calls'] = toolCallsJson
	    } else if (msg.role === 'tool') {
	      msgObj['content'] = msg.content
	      msgObj['tool_call_id'] = msg.toolCallId ?? ''
	      if (msg.name && msg.name.length > 0) {
	        msgObj['name'] = msg.name
	      }
    } else {
      msgObj['content'] = msg.content
    }

    serializedMessages.push(msgObj)
  }
  bodyObj['messages'] = serializedMessages

  // 工具声明
	  if (tools && tools.length > 0) {
	    bodyObj['tools'] = tools
	  }

  return JSON.stringify(bodyObj)
}

/**
 * 从 OpenAI 兼容流式 JSON 中提取文本增量。
 *
 * @param responseText - 单条 data JSON 字符串
 * @returns 文本增量（无内容时返回空字符串）
 */
function parseStreamDelta(responseText: string): string {
  try {
    const json: Record<string, Object> = JSON.parse(responseText) as Record<string, Object>
    const choices: Object[] = json['choices'] as Object[]
    if (!choices || choices.length === 0) {
      return ''
    }
    const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
    const delta: Record<string, Object> = firstChoice['delta'] as Record<string, Object>
    if (delta) {
      // 标准流式 delta.content（普通文本回复）
      const content: string = (delta['content'] as string) ?? ''
      if (content.length > 0) {
        return content
      }
      // 部分实现将内容放在 delta.message.content
      const msg: Record<string, Object> = delta['message'] as Record<string, Object>
      if (msg) {
        const msgContent: string = (msg['content'] as string) ?? ''
        if (msgContent.length > 0) {
          return msgContent
        }
      }
    }
    // 兼容非流式响应的 message 结构（某些 SSE 实现在最后 chunk 包含完整 message）
    const message: Record<string, Object> = firstChoice['message'] as Record<string, Object>
    if (message) {
      return (message['content'] as string) ?? ''
    }
    return ''
  } catch (e) {
    logger.warn('parseStreamDelta: 解析 chunk 失败: %{public}s', (e as Error).message ?? 'unknown')
    return ''
  }
}

/**
 * 从 OpenAI 兼容响应 JSON 中提取助手回复内容。
 *
 * @param responseText - 响应 JSON 字符串
 * @returns 助手回复文本
 */
function parseChatResponse(responseText: string): string {
  try {
    const json: Record<string, Object> = JSON.parse(responseText) as Record<string, Object>
    const choices: Object[] = json['choices'] as Object[]
    if (choices && choices.length > 0) {
      const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
      const message: Record<string, Object> = firstChoice['message'] as Record<string, Object>
      if (message) {
        return (message['content'] as string) ?? ''
      }
    }
    return ''
  } catch (e) {
    logger.error('parseChatResponse failed')
    return ''
  }
}

/**
 * 解析非流式响应，提取文本内容或工具调用。
 *
 * 模型可能选择调用工具（finish_reason === 'tool_calls'），
 * 此时 content 为空但 toolCalls 中有工具调用信息。
 *
 * @param responseText - 响应 JSON 字符串
 * @returns 包含文本或工具调用的解析结果
 */
function parseToolCallResponse(responseText: string): ToolCallResult {
  const result: ToolCallResult = new ToolCallResult()
  try {
    const json: Record<string, Object> = JSON.parse(responseText) as Record<string, Object>
    const choices: Object[] = json['choices'] as Object[]
    if (!choices || choices.length === 0) {
      return result
    }
    const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
    const finishReason: string = (firstChoice['finish_reason'] as string) ?? ''
    const message: Record<string, Object> = firstChoice['message'] as Record<string, Object>
    if (!message) {
      return result
    }

    // 提取文本内容
    result.content = (message['content'] as string) ?? ''

    // 提取工具调用
    if (finishReason === 'tool_calls' || message['tool_calls'] !== undefined) {
      const rawToolCalls: Object[] = message['tool_calls'] as Object[]
      if (rawToolCalls && rawToolCalls.length > 0) {
        for (let i = 0; i < rawToolCalls.length; i++) {
          const raw: Record<string, Object> = rawToolCalls[i] as Record<string, Object>
          const tc: ToolCall = new ToolCall()
          tc.id = (raw['id'] as string) ?? ''
          tc.type = (raw['type'] as string) ?? 'function'
          const func: Record<string, Object> = raw['function'] as Record<string, Object>
          if (func) {
            tc.function.name = (func['name'] as string) ?? ''
            tc.function.arguments = (func['arguments'] as string) ?? ''
          }
          result.toolCalls.push(tc)
        }
	        result.hasToolCalls = result.toolCalls.length > 0
	        if (logger.isVerbose()) {
	          logger.verbose('parseToolCallResponse: %d tool_calls, id[0]=%{public}s',
	            result.toolCalls.length, result.toolCalls[0].id)
	        }
      }
    }
  } catch (e) {
    logger.error('parseToolCallResponse failed')
  }
  return result
}

/**
 * 从 /models 接口响应 JSON 中提取模型 ID 列表。
 *
 * @param responseText - 响应 JSON 字符串
 * @returns 模型 ID 列表
 */
function parseModelList(responseText: string): string[] {
  const result: string[] = []
  try {
    const json: Record<string, Object> = JSON.parse(responseText) as Record<string, Object>
    const data: Object[] = json['data'] as Object[]
    if (data) {
      for (let i = 0; i < data.length; i++) {
        const item: Record<string, Object> = data[i] as Record<string, Object>
        const id: string = (item['id'] as string) ?? ''
        if (id.length > 0) {
          result.push(id)
        }
      }
    }
  } catch (e) {
    logger.error('parseModelList failed')
  }
  return result
}
