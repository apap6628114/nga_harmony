/**
 * AI 设置域子 store。
 *
 * 管理自定义 AI 提供方配置的增删改查及激活切换，
 * 遵循 SettingsContext 注入模式，子 store 之间无横向 import。
 */

import { SettingsContext } from '../SettingsContext'
import { SettingsState } from '../SettingsState'
import type { AiProviderProfile } from '../../../model/AiConfig'
import { KEY_AI_CONFIG_VERSION } from '../../../common/constants/AppStorageKeys'
import { bumpAppStorageVersion } from '../../../common/utils/AppStorageVersion'

/** 生成简单唯一 ID */
function generateId(): string {
  return 'ai_' + Date.now() + '_' + Math.floor(Math.random() * 10000)
}

/**
 * 补齐历史持久化配置中缺失的 AI 字段默认值。
 *
 * @param profile - 从持久化数据读取出的配置
 * @returns 已补齐默认值的配置
 */
function normalizeSavedProfile(profile: AiProviderProfile): AiProviderProfile {
  profile.streaming = profile.streaming !== false
  if (profile.temperature === undefined) {
    profile.temperature = 0.7
  }
  if (profile.maxTokens === undefined) {
    profile.maxTokens = 2000
  }
  profile.privacyConfirmed = profile.privacyConfirmed === true
  return profile
}

/**
 * AI 设置域子 store。
 *
 * 管理自定义 AI 提供方配置的增删改查及激活切换。
 */
export class AiSettings {
  /** 设置域上下文。 */
  private ctx: SettingsContext

  /**
   * 创建 AI 设置域子 store。
   *
   * @param ctx - 设置域共享上下文
   */
  constructor(ctx: SettingsContext) {
    this.ctx = ctx
  }

  /**
   * 添加新的 AI 提供方配置。
   *
   * @param profile - 新配置（id 字段被自动赋值）
   */
  addProfile(profile: AiProviderProfile): void {
    profile.id = generateId()
    this.ctx.state.aiProfiles = [...this.ctx.state.aiProfiles, profile]
    this.ctx.persist()
    this.notifyAiConfigChanged()
  }

  /**
   * 更新已有的 AI 提供方配置。
   *
   * @param profile - 已变更的配置
   */
  updateProfile(profile: AiProviderProfile): void {
    const newList: AiProviderProfile[] = []
    for (let i = 0; i < this.ctx.state.aiProfiles.length; i++) {
      if (this.ctx.state.aiProfiles[i].id === profile.id) {
        newList.push(profile)
      } else {
        newList.push(this.ctx.state.aiProfiles[i])
      }
    }
    this.ctx.state.aiProfiles = newList
    this.ctx.persist()
    this.notifyAiConfigChanged()
  }

  /**
   * 删除指定 ID 的 AI 提供方配置。
   *
   * 若删除的是当前激活配置，自动切换到剩余配置的第一项。
   *
   * @param id - 待删除的配置 ID
   */
  deleteProfile(id: string): void {
    const newList: AiProviderProfile[] = []
    for (let i = 0; i < this.ctx.state.aiProfiles.length; i++) {
      if (this.ctx.state.aiProfiles[i].id !== id) {
        newList.push(this.ctx.state.aiProfiles[i])
      }
    }
    this.ctx.state.aiProfiles = newList

    if (this.ctx.state.activeAiProfileId === id || !this.hasProfile(this.ctx.state.activeAiProfileId)) {
      this.ctx.state.activeAiProfileId = newList.length > 0 ? newList[0].id : ''
    }

    this.ctx.persist()
    this.notifyAiConfigChanged()
  }

  /**
   * 设置当前激活的 AI 配置。
   *
   * @param id - 配置 ID
   */
  setActiveProfile(id: string): void {
    this.ctx.state.activeAiProfileId = this.hasProfile(id) ? id : ''
    this.ctx.persist()
    this.notifyAiConfigChanged()
  }

  /**
   * 获取当前激活的 AI 配置。
   *
   * @returns 激活的配置，若未选择或配置已不存在则返回 null
   */
  getActiveProfile(): AiProviderProfile | null {
    for (let i = 0; i < this.ctx.state.aiProfiles.length; i++) {
      if (this.ctx.state.aiProfiles[i].id === this.ctx.state.activeAiProfileId) {
        return this.ctx.state.aiProfiles[i]
      }
    }
    return null
  }

  /** 从持久化对象加载 AI 设置 */
  load(saved: SettingsState): void {
    if (saved.aiProfiles) {
      const profiles: AiProviderProfile[] = []
      for (let i = 0; i < saved.aiProfiles.length; i++) {
        profiles.push(normalizeSavedProfile(saved.aiProfiles[i]))
      }
      this.ctx.state.aiProfiles = profiles
    }
    if (saved.activeAiProfileId !== undefined) {
      this.ctx.state.activeAiProfileId = this.hasProfile(saved.activeAiProfileId) ? saved.activeAiProfileId : ''
    }
  }

  /** 重置 AI 设置为默认，保留已配置的 profiles 由 SettingsState 重建时清空 */
  reset(): void {
  }

  /**
   * 判断指定配置是否存在。
   *
   * @param id - 配置 ID
   * @returns 配置是否存在
   */
  private hasProfile(id: string): boolean {
    if (id.length === 0) {
      return false
    }
    for (let i = 0; i < this.ctx.state.aiProfiles.length; i++) {
      if (this.ctx.state.aiProfiles[i].id === id) {
        return true
      }
    }
    return false
  }

  /**
   * 通知依赖 AI 配置摘要的页面刷新。
   */
  private notifyAiConfigChanged(): void {
    bumpAppStorageVersion(KEY_AI_CONFIG_VERSION)
  }
}
