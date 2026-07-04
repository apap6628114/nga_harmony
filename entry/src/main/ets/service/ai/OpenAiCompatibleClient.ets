/**
 * OpenAI 兼容 API 客户端。
 *
 * 支持向 OpenAI 兼容端点发送对话补全请求，
 * 提供测试连接、获取模型列表功能。
 */

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Logger, DOMAIN_APP } from '../../common/utils/Logger'
import type { AiProviderProfile } from '../../model/AiConfig'
import { AiTestResult } from '../../model/AiConfig'

const logger = new Logger(DOMAIN_APP, 'OpenAiClient')

/** 请求超时毫秒数 */
const REQUEST_TIMEOUT: number = 60000
/** 连接超时毫秒数 */
const CONNECT_TIMEOUT: number = 15000

/** 流式响应文本增量回调 */
export type ChatStreamChunkCallback = (chunk: string) => void

/** 对话消息 */
export class ChatMessage {
  /** 消息角色 */
  role: string
  /** 消息内容 */
  content: string

  /**
   * 创建对话消息。
   *
   * @param role - 消息角色
   * @param content - 消息内容
   */
  constructor(role: string, content: string) {
    this.role = role
    this.content = content
  }
}

/** 流式响应解析状态。 */
class ChatStreamParser {
  /** 尚未解析成完整 SSE 事件的文本。 */
  private pendingText: string = ''
  /** 已解析出的完整助手回复文本。 */
  private content: string = ''

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
      const delta: string = parseStreamDelta(dataText)
      if (delta.length > 0) {
        this.content += delta
        onDelta(delta)
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
        rejectOnce(new Error(String(statusCode)))
      }
    }).catch((err: Error): void => {
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
 * @returns JSON 字符串
 */
function buildRequestBody(
  profile: AiProviderProfile,
  messages: ChatMessage[],
  stream: boolean
): string {
  const bodyObj: Record<string, string | number | boolean | ChatMessage[]> = {}
  bodyObj['model'] = profile.modelName
  bodyObj['messages'] = messages
  bodyObj['stream'] = stream
  bodyObj['temperature'] = profile.temperature
  bodyObj['max_tokens'] = profile.maxTokens

  return JSON.stringify(bodyObj)
}

/**
 * 从 OpenAI 兼容流式 JSON 中提取文本增量。
 *
 * @param responseText - 单条 data JSON 字符串
 * @returns 文本增量
 */
function parseStreamDelta(responseText: string): string {
  const json: Record<string, Object> = JSON.parse(responseText) as Record<string, Object>
  const choices: Object[] = json['choices'] as Object[]
  if (!choices || choices.length === 0) {
    return ''
  }
  const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
  const delta: Record<string, Object> = firstChoice['delta'] as Record<string, Object>
  if (delta) {
    const content: string = (delta['content'] as string) ?? ''
    if (content.length > 0) {
      return content
    }
  }
  const message: Record<string, Object> = firstChoice['message'] as Record<string, Object>
  if (message) {
    return (message['content'] as string) ?? ''
  }
  return ''
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
