export enum BBNodeType {
  TEXT,
  BOLD,
  ITALIC,
  UNDERLINE,
  STRIKETHROUGH,
  COLOR,
  SIZE,
  FONT,
  URL,
  IMAGE,
  QUOTE,
  COLLAPSE,
  CODE,
  LIST,
  LIST_ITEM,
  PID_LINK,
  UID_LINK,
  TID_LINK,
  MENTION,
  POST_BY,
  EMOTION,
  VIDEO,
  AUDIO,
  DICE,
  WARN,
  ALBUM,
  FLOAT_LEFT,
  FLOAT_RIGHT,
  ALIGN,
  TABLE,
  TABLE_ROW,
  TABLE_CELL,
  STYLE_DIV,
  FLASH,
  HR,
  PARAGRAPH,
  SUBSCRIPT,
  SUPERSCRIPT,
}

export class BBNode {
  type: BBNodeType = BBNodeType.TEXT
  text: string = ''
  id: number = 0
  children: BBNode[] = []
  href: string = ''
  color: string = ''
  size: number = 0
  src: string = ''
  title: string = ''
  emotionCat: string = ''
  emotionCode: string = ''
  fontFamily: string = ''
  align: string = ''
  colSpan: number = 0
  rowSpan: number = 0
  colWidth: number = 0
}
