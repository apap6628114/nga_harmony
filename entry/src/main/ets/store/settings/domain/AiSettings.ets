/**
 * AI 设置域子 store。
 *
 * 管理自定义 AI 提供方配置的增删改查及激活切换，
 * 遵循 SettingsContext 注入模式，子 store 之间无横向 import。
 */

import { SettingsContext } from '../SettingsContext'
import { SettingsState } from '../SettingsState'
import type { AiProviderProfile } from '../../../model/AiConfig'

/** 生成简单唯一 ID */
function generateId(): string {
  return 'ai_' + Date.now() + '_' + Math.floor(Math.random() * 10000)
}

/**
 * AI 设置域子 store。
 *
 * 管理自定义 AI 提供方配置的增删改查及激活切换。
 */
export class AiSettings {
  private ctx: SettingsContext

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
  }

  /**
   * 删除指定 ID 的 AI 提供方配置。
   *
   * 若删除的是当前激活配置，自动回退到系统默认（index=-1）。
   *
   * @param id - 待删除的配置 ID
   */
  deleteProfile(id: string): void {
    const newList: AiProviderProfile[] = []
    let deletedIndex: number = -1
    let currentIndex: number = 0
    for (let i = 0; i < this.ctx.state.aiProfiles.length; i++) {
      if (this.ctx.state.aiProfiles[i].id === id) {
        deletedIndex = i
      } else {
        newList.push(this.ctx.state.aiProfiles[i])
        currentIndex++
      }
    }
    this.ctx.state.aiProfiles = newList

    // 若删除了当前激活配置，回退到系统默认
    if (deletedIndex === this.ctx.state.activeAiConfigIndex) {
      this.ctx.state.activeAiConfigIndex = -1
    } else if (deletedIndex < this.ctx.state.activeAiConfigIndex) {
      // 删除项在激活项之前，索引需要前移
      this.ctx.state.activeAiConfigIndex = this.ctx.state.activeAiConfigIndex - 1
    }

    this.ctx.persist()
  }

  /**
   * 设置当前激活的 AI 配置。
   *
   * @param index - 配置在列表中的索引（-1 表示系统默认 AI）
   */
  setActiveConfig(index: number): void {
    this.ctx.state.activeAiConfigIndex = index
    this.ctx.persist()
  }

  /**
   * 获取当前激活的 AI 配置。
   *
   * @returns 激活的配置，若为系统默认则返回 null
   */
  getActiveProfile(): AiProviderProfile | null {
    const idx: number = this.ctx.state.activeAiConfigIndex
    if (idx < 0 || idx >= this.ctx.state.aiProfiles.length) {
      return null
    }
    return this.ctx.state.aiProfiles[idx]
  }

  /** 从持久化对象加载 AI 设置 */
  load(saved: SettingsState): void {
    if (saved.aiProfiles) {
      this.ctx.state.aiProfiles = saved.aiProfiles
    }
    if (saved.activeAiConfigIndex !== undefined) {
      this.ctx.state.activeAiConfigIndex = saved.activeAiConfigIndex
    }
  }

  /** 重置 AI 设置为默认，保留已配置的 profiles 由 SettingsState 重建时清空 */
  reset(): void {
    // 内部状态由 SettingsState 构造函数重建，此处无需额外操作
  }
}
