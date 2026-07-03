/**
 * AI 提供方和模型预设数据。
 *
 * 提供流行 AI 服务商的端点地址预设及常用模型列表，
 * 降低用户手动输入端点地址的门槛。
 */

/** AI 服务商预设 */
export class AiProviderPreset {
  /** 服务商标识 */
  id: string
  /** 服务商名称 */
  name: string
  /** OpenAI 兼容端点地址 */
  endpoint: string
  /** 一句话说明 */
  description: string

  constructor(id: string, name: string, endpoint: string, description: string) {
    this.id = id
    this.name = name
    this.endpoint = endpoint
    this.description = description
  }
}

/** AI 模型预设 */
export class AiModelPreset {
  /** 模型名称 */
  modelName: string
  /** 用途说明 */
  description: string
  /** 所属服务商 ID */
  providerId: string

  constructor(modelName: string, description: string, providerId: string) {
    this.modelName = modelName
    this.description = description
    this.providerId = providerId
  }
}

/** 预设 AI 服务商列表 */
export const PROVIDER_PRESETS: AiProviderPreset[] = [
  new AiProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', '国产高性价比大模型'),
  new AiProviderPreset('zhipu', '智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', '清华系大模型'),
  new AiProviderPreset('openai', 'OpenAI', 'https://api.openai.com/v1', '全球领先的大模型'),
  new AiProviderPreset('moonshot', 'Moonshot', 'https://api.moonshot.cn/v1', '长文本处理能力强'),
  new AiProviderPreset('custom', '自定义', '', '手动输入端点地址')
]

/** 预设模型列表 */
export const MODEL_PRESETS: AiModelPreset[] = [
  new AiModelPreset('deepseek-chat', '通用对话 - 适合日常问答和分析', 'deepseek'),
  new AiModelPreset('deepseek-reasoner', '深度推理 - 适合复杂逻辑分析', 'deepseek'),
  new AiModelPreset('glm-4-flash', '快速通用 - 日常任务首选', 'zhipu'),
  new AiModelPreset('glm-4-plus', '旗舰性能 - 复杂分析场景', 'zhipu'),
  new AiModelPreset('gpt-4o', '通用多模态 - 支持图片理解', 'openai'),
  new AiModelPreset('gpt-4o-mini', '轻量快速 - 日常任务首选', 'openai'),
  new AiModelPreset('moonshot-v1-8k', '通用对话 - 中文优化', 'moonshot'),
  new AiModelPreset('moonshot-v1-32k', '长文本 - 适合分析大量内容', 'moonshot')
]

/**
 * 根据服务商 ID 获取对应的模型预设列表。
 *
 * @param providerId - 服务商标识
 * @returns 该服务商的模型预设列表
 */
export function getModelsByProvider(providerId: string): AiModelPreset[] {
  const result: AiModelPreset[] = []
  for (let i = 0; i < MODEL_PRESETS.length; i++) {
    if (MODEL_PRESETS[i].providerId === providerId) {
      result.push(MODEL_PRESETS[i])
    }
  }
  return result
}
