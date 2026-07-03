/**
 * AI 配置数据模型。
 *
 * 定义自定义 AI 提供方配置的数据结构及 AI 调用模式。
 */

/** AI 调用模式 */
export type AiCallMode = 'system' | 'custom'

/**
 * 自定义 AI 提供方配置。
 *
 * 每个配置代表一个第三方 OpenAI 兼容端点，
 * 包含连接信息、认证凭证及模型选择。
 */
export class AiProviderProfile {
  /** 唯一标识（生成时赋值） */
  id: string = ''
  /** 用户命名的方案名称 */
  name: string = ''
  /** OpenAI 兼容 API 端点地址（如 https://api.deepseek.com/v1） */
  endpoint: string = ''
  /** API 密钥（不记录到日志） */
  apiKey: string = ''
  /** 模型名称 */
  modelName: string = ''
  /** 是否启用流式输出 */
  streaming: boolean = true
  /** 温度参数（0.0 - 1.5，默认 0.7） */
  temperature: number = 0.7
  /** 输出上限（400 - 4000，默认 2000） */
  maxTokens: number = 2000
  /** 隐私确认是否已通过 */
  privacyConfirmed: boolean = false
}

/** 连接测试结果 */
export class AiTestResult {
  /** 是否成功 */
  success: boolean = false
  /** 模型回复文本（成功时） */
  message: string = ''
  /** 耗时（毫秒） */
  durationMs: number = 0
  /** 错误信息（失败时） */
  errorMessage: string = ''
}
