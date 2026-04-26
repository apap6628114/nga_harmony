import { BBNode } from '../model/BBCodeNode'
import { parseBBCode } from '../service/BBCodeParser'

const MAX_CACHE_SIZE: number = 150
const cache: Map<string, BBNode[]> = new Map()
const keyOrder: string[] = []

export function getCachedBBNodes(content: string): BBNode[] {
  const cached: BBNode[] | undefined = cache.get(content)
  if (cached) return cached

  const nodes: BBNode[] = parseBBCode(content)

  if (cache.size >= MAX_CACHE_SIZE && keyOrder.length > 0) {
    const oldest: string | undefined = keyOrder.shift()
    if (oldest) cache.delete(oldest)
  }
  cache.set(content, nodes)
  keyOrder.push(content)
  return nodes
}

export function clearBBCodeCache(): void {
  cache.clear()
  keyOrder.length = 0
}
