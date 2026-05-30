import { taskpool } from '@kit.ArkTS'
import { withTimeout } from '../common/TimeoutUtils'
import { BBNode, BBNodeType } from '../model/BBCodeNode'
import { parseBBCode } from './BBCodeParser'
import { parseBBCodeTask, BBNodeJSON } from './BBCodeParseTask'
import { LruCache } from '../common/LruCache'

const MAX_CACHE_SIZE: number = 150
const cache: LruCache<BBNode[]> = new LruCache<BBNode[]>(MAX_CACHE_SIZE)
const pendingSet: Set<string> = new Set()

function bbNodesFromJSON(json: string): BBNode[] {
  const raw: BBNodeJSON[] = JSON.parse(json) as BBNodeJSON[]
  const result: BBNode[] = []
  for (let i: number = 0; i < raw.length; i++) {
    result.push(jsonToBBNode(raw[i]))
  }
  return result
}

function jsonToBBNode(d: BBNodeJSON): BBNode {
  const n: BBNode = new BBNode()
  n.type = d.type as BBNodeType
  n.text = d.text
  n.id = d.id
  n.href = d.href
  n.color = d.color
  n.size = d.size
  n.src = d.src
  n.title = d.title
  n.emotionCat = d.emotionCat
  n.emotionCode = d.emotionCode
  n.fontFamily = d.fontFamily
  n.align = d.align
  n.colSpan = d.colSpan
  n.rowSpan = d.rowSpan
  n.colWidth = d.colWidth
  const childCount: number = d.children.length
  for (let i: number = 0; i < childCount; i++) {
    n.children.push(jsonToBBNode(d.children[i]))
  }
  return n
}

export function getCachedBBNodes(content: string): BBNode[] {
  const cached: BBNode[] | undefined = cache.get(content)
  if (cached) return cached

  const nodes: BBNode[] = parseBBCode(content)
  cache.set(content, nodes)
  return nodes
}

export function clearBBCodeCache(): void {
  cache.clear()
}

export function preWarmBBCache(content: string): void {
  preWarmBatch([content], taskpool.Priority.MEDIUM)
}

export function preWarmBatch(contents: string[], priority?: taskpool.Priority): void {
  preWarmBatchAwait(contents, priority).catch((err: Error) => {
    console.error('preWarmBatch failed:', err.message)
  })
}

export async function preWarmBatchAwait(contents: string[], priority?: taskpool.Priority): Promise<void> {
  const toParse: string[] = []
  for (let i: number = 0; i < contents.length; i++) {
    const c: string = contents[i]
    if (!c || cache.has(c) || pendingSet.has(c)) continue
    toParse.push(c)
    pendingSet.add(c)
  }
  if (toParse.length === 0) return

  const p: taskpool.Priority = priority !== undefined ? priority : taskpool.Priority.MEDIUM
  const group: taskpool.TaskGroup = new taskpool.TaskGroup()
  for (let i: number = 0; i < toParse.length; i++) {
    group.addTask(new taskpool.Task(parseBBCodeTask, toParse[i]))
  }
  const results: Object[] = await withTimeout<Object[]>(
    taskpool.execute(group, p) as Promise<Object[]>,
    10000
  ) as Object[]
  for (let i: number = 0; i < results.length; i++) {
    cache.set(toParse[i], bbNodesFromJSON(results[i] as string))
    pendingSet.delete(toParse[i])
  }
}
