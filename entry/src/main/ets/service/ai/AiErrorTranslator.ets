/**
 * AI 调用错误翻译工具。
 *
 * 将 HTTP 状态码和网络错误映射为用户友好的中文提示，
 * 并提供对应的修复操作建议，降低用户理解门槛。
 */

/** 错误修复操作 */
export enum AiErrorAction {
  /** 更新 API 密钥 */
  UPDATE_KEY = 'update_key',
  /** 检查网络设置 */
  CHECK_NETWORK = 'check_network',
  /** 重试 */
  RETRY = 'retry',
  /** 检查端点地址 */
  CHECK_ENDPOINT = 'check_endpoint',
  /** 检查模型名称 */
  CHECK_MODEL = 'check_model'
}

/** 翻译后的用户友好错误信息 */
export class AiErrorInfo {
  /** 用户可读的错误描述 */
  userMessage: string
  /** 修复建议 */
  suggestion: string
  /** 建议执行的操作 */
  action: AiErrorAction

  constructor(userMessage: string, suggestion: string, action: AiErrorAction) {
    this.userMessage = userMessage
    this.suggestion = suggestion
    this.action = action
  }
}

/**
 * 将 HTTP 状态码或网络错误码翻译为用户友好的错误信息。
 *
 * @param statusCode - HTTP 状态码，或负数表示网络错误
 * @param rawMessage - 原始错误消息
 * @returns 翻译后的用户友好错误信息
 */
export function translateError(statusCode: number, rawMessage?: string): AiErrorInfo {
  // HTTP 401 — 认证失败
  if (statusCode === 401) {
    return new AiErrorInfo(
      'API 密钥无效或已过期',
      '请前往 AI 配置页面更新密钥',
      AiErrorAction.UPDATE_KEY
    )
  }
  // HTTP 403 — 权限不足
  if (statusCode === 403) {
    return new AiErrorInfo(
      'API 密钥无权访问该资源',
      '请确认密钥权限是否包含模型调用，或更换密钥',
      AiErrorAction.UPDATE_KEY
    )
  }
  // HTTP 404 — 端点或模型不存在
  if (statusCode === 404) {
    return new AiErrorInfo(
      '服务地址或模型不存在',
      '请检查端点地址是否正确，或确认模型名称是否有效',
      AiErrorAction.CHECK_ENDPOINT
    )
  }
  // HTTP 429 — 速率限制/额度用完
  if (statusCode === 429) {
    return new AiErrorInfo(
      'API 请求额度已用尽或请求过于频繁',
      '请稍后重试，或检查账户余额',
      AiErrorAction.RETRY
    )
  }
  // HTTP 400 — 请求参数错误（通常是模型名不对）
  if (statusCode === 400) {
    return new AiErrorInfo(
      '请求参数不正确',
      '请检查模型名称是否填写正确',
      AiErrorAction.CHECK_MODEL
    )
  }
  // HTTP 5xx — 服务端错误
  if (statusCode >= 500 && statusCode < 600) {
    return new AiErrorInfo(
      'AI 服务暂时不可用',
      '服务端出现异常，请稍后重试',
      AiErrorAction.RETRY
    )
  }
  // 连接超时 / DNS 解析失败（负值网络错误码）
  if (statusCode < 0) {
    return new AiErrorInfo(
      '无法连接到 AI 服务',
      '请检查网络连接，或确认服务地址是否正确',
      AiErrorAction.CHECK_NETWORK
    )
  }
  // 默认
  return new AiErrorInfo(
    rawMessage ? `AI 调用失败：${rawMessage}` : 'AI 调用失败',
    '请检查配置或稍后重试',
    AiErrorAction.RETRY
  )
}
