/**
 * 自定义 AI 激活配置与调用门面。
 *
 * 统一封装当前激活的用户自定义 AI 配置校验、调用与错误文案，
 * 页面层不再直接处理配置索引或额外调用分支。
 */

import { appStore } from '../../store/AppStore'
import type { AiProviderProfile } from '../../model/AiConfig'
import { chatComplete, chatCompleteStream } from './OpenAiCompatibleClient'
import type { ChatMessage, ChatStreamChunkCallback } from './OpenAiCompatibleClient'
import { translateError } from './AiErrorTranslator'

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
 *
 * @param messages - 对话消息列表
 * @param onDelta - 文本增量回调
 * @returns 模型返回的完整文本
 */
export async function chatCompleteWithActiveAiStream(
  messages: ChatMessage[],
  onDelta: ChatStreamChunkCallback
): Promise<string> {
  const profile: AiProviderProfile | null = getActiveAiProfile()
  const validationMessage: string = getActiveAiValidationMessage()
  if (!profile || validationMessage.length > 0) {
    throw new Error(validationMessage.length > 0 ? validationMessage : '请先在设置中选择 AI 配置')
  }
  if (!profile.streaming) {
    const result: string = await chatComplete(profile, messages)
    onDelta(result)
    return result
  }
  return chatCompleteStream(profile, messages, onDelta)
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
