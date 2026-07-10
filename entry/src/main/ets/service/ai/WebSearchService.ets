/**
 * Tavily 搜索 API 客户端。
 *
 * 用于在 AI Function Calling 流程中提供联网搜索能力，
 * 返回结构化搜索结果。
 */

import { http } from '@kit.NetworkKit'
import { Logger, DOMAIN_SERVICE } from '../../common/utils/Logger'

const logger = new Logger(DOMAIN_SERVICE, 'WebSearchSvc')

/** Tavily API 基础地址 */
const TAVILY_BASE_URL: string = 'https://api.tavily.com'
/** 搜索超时毫秒数 */
const SEARCH_TIMEOUT: number = 15000

/** 单条搜索结果。 */
export class SearchResultItem {
  /** 标题 */
  title: string = ''
  /** 链接 */
  url: string = ''
  /** 内容摘要 */
  content: string = ''
  /** 相关性评分（0~1） */
  score: number = 0
}

/** Tavily 搜索响应。 */
export class SearchResponse {
  /** AI 生成的答案摘要 */
  answer: string = ''
  /** 搜索结果列表 */
  results: SearchResultItem[] = []
  /** 是否成功 */
  success: boolean = false
  /** 错误信息 */
  errorMessage: string = ''
}

/**
 * 执行 Tavily 网页搜索。
 *
 * @param query - 搜索关键词或问题
 * @param apiKey - Tavily API 密钥
 * @returns 搜索结果
 */
export async function searchWeb(query: string, apiKey: string): Promise<SearchResponse> {
  const result: SearchResponse = new SearchResponse()

  if (query.trim().length === 0) {
    result.errorMessage = '搜索关键词不能为空'
    return result
  }
  if (apiKey.trim().length === 0) {
    result.errorMessage = 'Tavily API 密钥未配置'
    return result
  }

  const url: string = TAVILY_BASE_URL + '/search'
  const body: Record<string, Object> = {
    'query': query,
    'search_depth': 'basic',
    'max_results': 5,
    'include_answer': true
  }

  const httpRequest: http.HttpRequest = http.createHttp()
  try {
    const response: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + apiKey
      },
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      readTimeout: SEARCH_TIMEOUT,
      connectTimeout: 10000
    })

    const statusCode: number = response.responseCode
    const responseText: string = (response.result as string) ?? ''

    if (statusCode !== 200) {
      result.errorMessage = 'Tavily 搜索失败: HTTP ' + statusCode
      logger.error('Tavily search failed: HTTP %{public}d', statusCode)
      return result
    }

    const json: Record<string, Object> = JSON.parse(responseText) as Record<string, Object>
    result.answer = (json['answer'] as string) ?? ''

    const rawResults: Object[] = json['results'] as Object[]
    if (rawResults) {
      for (let i = 0; i < rawResults.length; i++) {
        const raw: Record<string, Object> = rawResults[i] as Record<string, Object>
        const item: SearchResultItem = new SearchResultItem()
        item.title = (raw['title'] as string) ?? ''
        item.url = (raw['url'] as string) ?? ''
        item.content = (raw['content'] as string) ?? ''
        item.score = (raw['score'] as number) ?? 0
        result.results.push(item)
      }
    }

    result.success = true
    return result
  } catch (e) {
    const err: Error = e as Error
    result.errorMessage = 'Tavily 搜索异常: ' + (err.message || '未知错误')
    logger.error('Tavily search exception: %{public}s', result.errorMessage)
    return result
  } finally {
    httpRequest.destroy()
  }
}
