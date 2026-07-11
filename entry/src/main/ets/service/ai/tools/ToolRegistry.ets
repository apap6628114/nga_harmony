/**
 * 工具注册中心。
 *
 * 管理所有 Function Calling 工具适配器的注册与查询，
 * 为服务层提供统一的工具发现与分发入口。
 */

import type { ToolAdapter } from './ToolAdapter'

/**
 * 工具注册中心。
 *
 * 采用注册制：各工具适配器在初始化时注册到中心，
 * 服务层通过中心获取可用工具列表和分发执行。
 */
export class ToolRegistry {
  /** 已注册的工具适配器列表。 */
  private adapters: ToolAdapter[] = []

  /**
   * 注册工具适配器。
   *
   * @param adapter - 工具适配器实例
   */
  register(adapter: ToolAdapter): void {
    this.adapters.push(adapter)
  }

  /**
   * 获取当前所有可用的工具适配器。
   *
   * @returns 通过 isAvailable() 筛选后的适配器列表
   */
  getAvailableAdapters(): ToolAdapter[] {
    const available: ToolAdapter[] = []
    for (let i = 0; i < this.adapters.length; i++) {
      if (this.adapters[i].isAvailable()) {
        available.push(this.adapters[i])
      }
    }
    return available
  }

  /**
   * 获取当前所有可用工具的 OpenAI Function Calling 定义。
   *
   * @returns 符合 OpenAI tools 数组格式的对象列表
   */
  getToolDefinitions(): Object[] {
    const available: ToolAdapter[] = this.getAvailableAdapters()
    const definitions: Object[] = []
    for (let i = 0; i < available.length; i++) {
      definitions.push(available[i].getDefinition())
    }
    return definitions
  }

  /**
   * 按工具名称查找适配器。
   *
   * @param name - 工具名称（对应 OpenAI function.name）
   * @returns 适配器实例，未找到或不可用时返回 null
   */
  getAdapter(name: string): ToolAdapter | null {
    for (let i = 0; i < this.adapters.length; i++) {
      const def: Record<string, Object> = this.adapters[i].getDefinition() as Record<string, Object>
      const funcDef: Record<string, Object> = def['function'] as Record<string, Object>
      if ((funcDef['name'] as string) === name && this.adapters[i].isAvailable()) {
        return this.adapters[i]
      }
    }
    return null
  }
}
