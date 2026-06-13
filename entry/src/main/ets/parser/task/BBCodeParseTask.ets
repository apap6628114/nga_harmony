import { BBNode } from '../../model/BBCodeNode'
import { parseBBCode } from '../bbcode/BBCodeParser'

interface BBNodeJSON {
  type: number
  text: string
  id: number
  children: BBNodeJSON[]
  href: string
  color: string
  size: number
  src: string
  title: string
  emotionCat: string
  emotionCode: string
  fontFamily: string
  align: string
  colSpan: number
  rowSpan: number
  colWidth: number
}

@Concurrent
function parseBBCodeTask(content: string): string {
  try {
    const nodes: BBNode[] = parseBBCode(content)
    return JSON.stringify(nodes)
  } catch (e) {
    return '[]'
  }
}

export { parseBBCodeTask, BBNodeJSON }
