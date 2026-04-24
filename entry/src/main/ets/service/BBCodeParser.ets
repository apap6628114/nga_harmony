import { BBNode, BBNodeType } from '../model/BBCodeNode'

const NGA_CDN_BASE: string = 'https://img.nga.178.com/attachments'

const CLOSE_TAG_PATTERN: RegExp = /\[\/(b|i|u|del|h|item|color|size|font|url|img|pid|uid|tid|quote|collapse|code|list|flash|lessernuke|album|hip|dice|align|style|table|tr|td|l|r|randomblock)\]/gi

interface FormatRecord {
  open: RegExp
  close: string
  type: BBNodeType
}

function stripThumb(url: string): string {
  return url
    .replace(/\.thumb_s\.\w+$/i, '')
    .replace(/\.thumb_m\.\w+$/i, '')
    .replace(/\.medium\.\w+$/i, '')
    .replace(/\.thumb\.\w+$/i, '')
}

function resolveImgUrl(raw: string): string {
  if (raw.startsWith('http')) return stripThumb(raw)
  if (raw.startsWith('/mon_') || raw.startsWith('./mon_')) {
    const path = raw.startsWith('./') ? raw.substring(1) : raw
    return NGA_CDN_BASE + stripThumb(path)
  }
  if (raw.startsWith('/')) return NGA_CDN_BASE + stripThumb(raw)
  return stripThumb(raw)
}

function escAngle(s: string): string {
  return s.replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function decodeHtmlEntities(s: string): string {
  return s
    .replace(/&#91;/g, '[')
    .replace(/&#93;/g, ']')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
}

function escSegHtml(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
}

class ParseState {
  content: string = ''
  pos: number = 0
  len: number = 0
}

function pushTextNode(into: BBNode[], text: string): void {
  if (text.length === 0) return
  const n = new BBNode()
  n.type = BBNodeType.TEXT
  n.text = text
  into.push(n)
}

function preprocessContent(s: string): string {
  return s
    .replace(/&#91;/g, '[')
    .replace(/&#93;/g, ']')
    .replace(/<blockquote[^>]*>/gi, '[quote]')
    .replace(/<\/blockquote>/gi, '[/quote]')
}

function parseBBCode(content: string): BBNode[] {
  if (!content) return []
  const state = new ParseState()
  state.content = preprocessContent(content)
  state.pos = 0
  state.len = state.content.length
  return parseBlockNodes(state, null)
}

function parseBlockNodes(state: ParseState, closePattern: RegExp | null): BBNode[] {
  const result: BBNode[] = []
  let blockPos: number = state.pos

  while (state.pos < state.len) {
    if (closePattern) {
      closePattern.lastIndex = state.pos
      const cm = closePattern.exec(state.content)
      if (cm && cm.index === state.pos) {
        if (state.pos > blockPos) {
          const seg = decodeHtmlEntities(state.content.substring(blockPos, state.pos))
          parseInlineInto(seg, result)
        }
        state.pos = closePattern.lastIndex
        return result
      }
    }

    const idx = state.content.indexOf('[', state.pos)
    if (idx < 0) {
      if (state.len > blockPos) {
        const remaining = decodeHtmlEntities(state.content.substring(blockPos, state.len))
        parseInlineInto(remaining, result)
      }
      state.pos = state.len
      blockPos = state.len
      break
    }

    if (idx > state.pos) {
      const seg = decodeHtmlEntities(state.content.substring(blockPos, idx))
      parseInlineInto(seg, result)
      blockPos = idx
    }
    state.pos = idx

    if (tryMatchBlock(state, result)) {
      blockPos = state.pos
      continue
    }

    if (closePattern) {
      closePattern.lastIndex = idx
      const cmAtIdx = closePattern.exec(state.content)
      if (cmAtIdx && cmAtIdx.index === idx) {
        if (idx > blockPos) {
          const seg = decodeHtmlEntities(state.content.substring(blockPos, idx))
          parseInlineInto(seg, result)
        }
        state.pos = closePattern.lastIndex
        return result
      }
    }

    state.pos = idx + 1
  }

  if (state.pos > blockPos && blockPos < state.len) {
    const remaining = decodeHtmlEntities(state.content.substring(blockPos, state.pos))
    parseInlineInto(remaining, result)
  }
  return result
}

function tryMatchBlock(state: ParseState, result: BBNode[]): boolean {
  const savedPos = state.pos

  let pReplyRef: RegExp = /\[b\]Reply to \[/gi
  pReplyRef.lastIndex = state.pos
  const rrm = pReplyRef.exec(state.content)
  if (rrm && rrm.index === state.pos) {
    state.pos = pReplyRef.lastIndex
    const closeIdx = state.content.indexOf('[/b]', state.pos)
    if (closeIdx >= 0) {
      const body = state.content.substring(state.pos, closeIdx)
      state.pos = closeIdx + 4
      const n = new BBNode()
      n.type = BBNodeType.POST_BY
      const childNodes: BBNode[] = []
      parseInlineInto('Reply to [' + body, childNodes)
      n.children = childNodes
      result.push(n)
      return true
    }
  }
  state.pos = savedPos

  let pQuote: RegExp = /\[quote\]/gi
  pQuote.lastIndex = state.pos
  const qm = pQuote.exec(state.content)
  if (qm && qm.index === state.pos) {
    state.pos = pQuote.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.QUOTE
    let pCloseQuote: RegExp = /\[\/quote\]/gi
    n.children = parseBlockNodes(state, pCloseQuote)
    result.push(n)
    return true
  }

  let pCollapse: RegExp = /\[collapse=(.*?)\]/gi
  pCollapse.lastIndex = state.pos
  const cm = pCollapse.exec(state.content)
  if (cm && cm.index === state.pos) {
    const title = cm[1]
    state.pos = pCollapse.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.COLLAPSE
    n.title = escAngle(title)
    let pCloseCollapse: RegExp = /\[\/collapse\]/gi
    n.children = parseBlockNodes(state, pCloseCollapse)
    result.push(n)
    return true
  }

  let pCode: RegExp = /\[code\]/gi
  pCode.lastIndex = state.pos
  const cdm = pCode.exec(state.content)
  if (cdm && cdm.index === state.pos) {
    state.pos = pCode.lastIndex
    let end = state.content.indexOf('[/code]', state.pos)
    if (end < 0) end = state.len
    const codeText = state.content.substring(state.pos, end)
    state.pos = end < state.len ? end + 7 : state.len
    const n = new BBNode()
    n.type = BBNodeType.CODE
    n.text = escAngle(codeText)
    result.push(n)
    return true
  }

  let pList: RegExp = /\[list\]/gi
  pList.lastIndex = state.pos
  const lm = pList.exec(state.content)
  if (lm && lm.index === state.pos) {
    state.pos = pList.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.LIST
    n.children = parseListItems(state)
    result.push(n)
    return true
  }

  let pNuke: RegExp = /\[lessernuke\]/gi
  pNuke.lastIndex = state.pos
  const lnm = pNuke.exec(state.content)
  if (lnm && lnm.index === state.pos) {
    state.pos = pNuke.lastIndex
    let end = state.content.indexOf('[/lessernuke]', state.pos)
    if (end < 0) end = state.len
    state.pos = end < state.len ? end + 13 : state.len
    const n = new BBNode()
    n.type = BBNodeType.WARN
    const bodyContent = parseBBCode(decodeHtmlEntities(
      state.content.substring(pNuke.lastIndex, end < state.len ? end : state.len)
    ))
    n.children = bodyContent
    result.push(n)
    return true
  }

  let pAlbum: RegExp = /\[album=(.*?)\]/gi
  pAlbum.lastIndex = state.pos
  const am = pAlbum.exec(state.content)
  if (am && am.index === state.pos) {
    const albumTitle = am[1]
    state.pos = pAlbum.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.ALBUM
    n.title = escAngle(albumTitle)
    let pCloseAlbum: RegExp = /\[\/album\]/gi
    n.children = parseBlockNodes(state, pCloseAlbum)
    result.push(n)
    return true
  }

  let pFv: RegExp = /\[flash=video\]/gi
  pFv.lastIndex = state.pos
  const fvm = pFv.exec(state.content)
  if (fvm && fvm.index === state.pos) {
    state.pos = pFv.lastIndex
    let end = state.content.indexOf('[/flash]', state.pos)
    if (end < 0) end = state.len
    const url = state.content.substring(state.pos, end)
    state.pos = end < state.len ? end + 8 : state.len
    const n = new BBNode()
    n.type = BBNodeType.VIDEO
    n.src = url.trim()
    result.push(n)
    return true
  }

  let pFa: RegExp = /\[flash=audio\]/gi
  pFa.lastIndex = state.pos
  const fam = pFa.exec(state.content)
  if (fam && fam.index === state.pos) {
    state.pos = pFa.lastIndex
    let end = state.content.indexOf('[/flash]', state.pos)
    if (end < 0) end = state.len
    const url = state.content.substring(state.pos, end)
    state.pos = end < state.len ? end + 8 : state.len
    const n = new BBNode()
    n.type = BBNodeType.AUDIO
    n.src = url.trim()
    result.push(n)
    return true
  }

  let pFlash: RegExp = /\[flash\](.*?)\[\/flash\]/gi
  pFlash.lastIndex = state.pos
  const ffm = pFlash.exec(state.content)
  if (ffm && ffm.index === state.pos) {
    state.pos = pFlash.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.FLASH
    n.href = ffm[1].trim()
    result.push(n)
    return true
  }

  let pDice: RegExp = /\[dice\](.*?)\[\/dice\]/gi
  pDice.lastIndex = state.pos
  const dm = pDice.exec(state.content)
  if (dm && dm.index === state.pos) {
    state.pos = pDice.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.DICE
    result.push(n)
    return true
  }

  let pNgaImg: RegExp = /\[img\]\.(\/mon_\S+?)\[\/img\]/gi
  pNgaImg.lastIndex = state.pos
  const ncm = pNgaImg.exec(state.content)
  if (ncm && ncm.index === state.pos) {
    const rawUrl = ncm[1]
    state.pos = pNgaImg.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.IMAGE
    n.src = resolveImgUrl(rawUrl)
    result.push(n)
    return true
  }

  let pImg: RegExp = /\[img\](.*?)\[\/img\]/gi
  pImg.lastIndex = state.pos
  const im = pImg.exec(state.content)
  if (im && im.index === state.pos) {
    const rawUrl = im[1]
    state.pos = pImg.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.IMAGE
    n.src = resolveImgUrl(rawUrl)
    result.push(n)
    return true
  }

  let pFloatL: RegExp = /\[l\]/gi
  pFloatL.lastIndex = state.pos
  const flm = pFloatL.exec(state.content)
  if (flm && flm.index === state.pos) {
    state.pos = pFloatL.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.FLOAT_LEFT
    let pCloseL: RegExp = /\[\/l\]/gi
    n.children = parseBlockNodes(state, pCloseL)
    result.push(n)
    return true
  }

  let pFloatR: RegExp = /\[r\]/gi
  pFloatR.lastIndex = state.pos
  const frm = pFloatR.exec(state.content)
  if (frm && frm.index === state.pos) {
    state.pos = pFloatR.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.FLOAT_RIGHT
    let pCloseR: RegExp = /\[\/r\]/gi
    n.children = parseBlockNodes(state, pCloseR)
    result.push(n)
    return true
  }

  let pAlign: RegExp = /\[align=(\w+)\]/gi
  pAlign.lastIndex = state.pos
  const alm = pAlign.exec(state.content)
  if (alm && alm.index === state.pos) {
    const alignVal = alm[1]
    state.pos = pAlign.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.ALIGN
    n.align = alignVal
    let pCloseAlign: RegExp = /\[\/align\]/gi
    n.children = parseBlockNodes(state, pCloseAlign)
    result.push(n)
    return true
  }

  let pTable: RegExp = /\[table\]/gi
  pTable.lastIndex = state.pos
  const tm = pTable.exec(state.content)
  if (tm && tm.index === state.pos) {
    state.pos = pTable.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.TABLE
    let pCloseTable: RegExp = /\[\/table\]/gi
    n.children = parseTableContent(state, pCloseTable)
    result.push(n)
    return true
  }

  let pStyle: RegExp = /\[style\s+([^\]]*)\]/gi
  pStyle.lastIndex = state.pos
  const sm = pStyle.exec(state.content)
  if (sm && sm.index === state.pos) {
    const styleVal = sm[1]
    state.pos = pStyle.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.STYLE_DIV
    n.text = styleVal
    let pCloseStyle: RegExp = /\[\/style\]/gi
    n.children = parseBlockNodes(state, pCloseStyle)
    result.push(n)
    return true
  }

  let pHip: RegExp = /\[hip\]/gi
  pHip.lastIndex = state.pos
  const hipm = pHip.exec(state.content)
  if (hipm && hipm.index === state.pos) {
    state.pos = pHip.lastIndex
    let end = state.content.indexOf('[/hip]', state.pos)
    if (end < 0) end = state.len
    const body = state.content.substring(state.pos, end)
    state.pos = end < state.len ? end + 6 : state.len
    const innerNodes = parseBBCode(decodeHtmlEntities(body))
    for (let k = 0; k < innerNodes.length; k++) {
      result.push(innerNodes[k])
    }
    return true
  }

  let pComment: RegExp = /\[comment[^\]]*\]/gi
  pComment.lastIndex = state.pos
  const comt = pComment.exec(state.content)
  if (comt && comt.index === state.pos) {
    state.pos = pComment.lastIndex
    return true
  }

  let pRandom: RegExp = /\[randomblock\]/gi
  pRandom.lastIndex = state.pos
  const rbm = pRandom.exec(state.content)
  if (rbm && rbm.index === state.pos) {
    state.pos = pRandom.lastIndex
    const n = new BBNode()
    n.type = BBNodeType.STYLE_DIV
    n.text = 'nga-randomblock'
    result.push(n)
    return true
  }

  state.pos = savedPos
  return false
}

function parseTableContent(state: ParseState, closePattern: RegExp): BBNode[] {
  const rows: BBNode[] = []
  while (state.pos < state.len) {
    closePattern.lastIndex = state.pos
    const cm = closePattern.exec(state.content)
    if (cm && cm.index === state.pos) {
      state.pos = closePattern.lastIndex
      return rows
    }

    let pTr: RegExp = /\[tr\]/gi
    pTr.lastIndex = state.pos
    const trm = pTr.exec(state.content)
    if (trm && trm.index === state.pos) {
      state.pos = pTr.lastIndex
      const row = new BBNode()
      row.type = BBNodeType.TABLE_ROW
      row.children = parseTableRowCells(state)
      rows.push(row)
      continue
    }
    state.pos = state.pos + 1
  }
  return rows
}

function parseTableRowCells(state: ParseState): BBNode[] {
  const cells: BBNode[] = []
  while (state.pos < state.len) {
    const trClose = state.content.indexOf('[/tr]', state.pos)
    const tdOpen = state.content.indexOf('[td', state.pos)
    if (tdOpen < 0 || (trClose >= 0 && trClose < tdOpen)) {
      if (trClose >= 0) state.pos = trClose + 5
      break
    }

    let pTd: RegExp = /\[td(?:=(\d+))?(?:,(\d+))?(?:,(\d+))?\]/gi
    pTd.lastIndex = state.pos
    const tdm = pTd.exec(state.content)
    if (tdm && tdm.index === state.pos) {
      state.pos = pTd.lastIndex
      const cell = new BBNode()
      cell.type = BBNodeType.TABLE_CELL
      if (tdm[1]) cell.colSpan = parseInt(tdm[1], 10)
      if (tdm[2]) cell.rowSpan = parseInt(tdm[2], 10)
      if (tdm[3]) cell.colWidth = parseInt(tdm[3], 10)

      const closeTdIdx = state.content.indexOf('[/td]', state.pos)
      const cellEnd = closeTdIdx >= 0 ? closeTdIdx : state.len
      const cellText = decodeHtmlEntities(state.content.substring(state.pos, cellEnd))
      state.pos = closeTdIdx >= 0 ? cellEnd + 5 : state.len
      cell.children = parseBBCode(cellText)
      cells.push(cell)
    } else {
      state.pos = state.pos + 1
    }
  }
  return cells
}

function parseListItems(state: ParseState): BBNode[] {
  const items: BBNode[] = []
  while (state.pos < state.len) {
    const starIdx = state.content.indexOf('[*]', state.pos)
    const closeIdx = state.content.indexOf('[/list]', state.pos)
    if (starIdx < 0 || (closeIdx >= 0 && starIdx > closeIdx)) {
      if (closeIdx >= 0) state.pos = closeIdx + 7
      else state.pos = state.len
      break
    }
    state.pos = starIdx + 3
    let itemEnd = state.content.indexOf('[*]', state.pos)
    const listClose = state.content.indexOf('[/list]', state.pos)
    if (itemEnd < 0 || (listClose >= 0 && itemEnd > listClose)) {
      itemEnd = listClose >= 0 ? listClose : state.len
    }
    const itemText = decodeHtmlEntities(state.content.substring(state.pos, itemEnd))
    state.pos = itemEnd
    const n = new BBNode()
    n.type = BBNodeType.LIST_ITEM
    n.children = parseBBCode(itemText.trim())
    items.push(n)
  }
  return items
}

function parseInlineInto(seg: string, into: BBNode[]): void {
  let i = 0
  const segLen = seg.length

  while (i < segLen) {
    const ch = seg[i]

    if (ch === '[') {
      const pidP: RegExp = /\[pid=(\d+),(\d+),(\d+)\](.*?)\[\/pid\]/g
      pidP.lastIndex = i
      const pidM = pidP.exec(seg)
      if (pidM && pidM.index === i) {
        i = pidP.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.PID_LINK
        n.href = `#/thread?tid=${pidM[2]}&pid=${pidM[1]}`
        n.text = escSegHtml(pidM[4])
        into.push(n)
        continue
      }

      const uidP: RegExp = /\[uid=(\d+)\](.*?)\[\/uid\]/g
      uidP.lastIndex = i
      const uidM = uidP.exec(seg)
      if (uidM && uidM.index === i) {
        i = uidP.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.UID_LINK
        n.href = `#/profile?uid=${uidM[1]}`
        n.text = escSegHtml(uidM[2])
        into.push(n)
        continue
      }

      const tidP: RegExp = /\[tid=(\d+)(?:&page=(\d+))?\](.*?)\[\/tid\]/g
      tidP.lastIndex = i
      const tidM = tidP.exec(seg)
      if (tidM && tidM.index === i) {
        i = tidP.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.TID_LINK
        n.href = `#/thread?tid=${tidM[1]}${tidM[2] ? '&page=' + tidM[2] : ''}`
        n.text = escSegHtml(tidM[3])
        into.push(n)
        continue
      }

      const menP: RegExp = /\[@(\d+)\]/g
      menP.lastIndex = i
      const menM = menP.exec(seg)
      if (menM && menM.index === i) {
        i = menP.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.MENTION
        n.href = `#/profile?uid=${menM[1]}`
        n.text = `@${menM[1]}`
        into.push(n)
        continue
      }

      const emo1P: RegExp = /\[s:(\w+):([^\]]+)\]/g
      emo1P.lastIndex = i
      const emo1M = emo1P.exec(seg)
      if (emo1M && emo1M.index === i) {
        i = emo1P.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.EMOTION
        n.emotionCat = emo1M[1]
        n.emotionCode = emo1M[2]
        into.push(n)
        continue
      }

      const emo2P: RegExp = /\[s:(\d+)\]/g
      emo2P.lastIndex = i
      const emo2M = emo2P.exec(seg)
      if (emo2M && emo2M.index === i) {
        i = emo2P.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.EMOTION
        n.emotionCat = 'old'
        n.emotionCode = emo2M[1]
        n.text = `[表情${emo2M[1]}]`
        into.push(n)
        continue
      }

      const pbP: RegExp = /Post by (.+?) \((\d+)\)/g
      pbP.lastIndex = i
      const pbM = pbP.exec(seg)
      if (pbM && pbM.index === i) {
        i = pbP.lastIndex
        pushTextNode(into, 'Post by ')
        const n = new BBNode()
        n.type = BBNodeType.UID_LINK
        n.href = `#/profile?uid=${pbM[2]}`
        n.text = escSegHtml(pbM[1])
        into.push(n)
        pushTextNode(into, ` (${pbM[2]})`)
        continue
      }

      let fmtMatched = false
      const closedFmtIndex: number = checkInlineFormat(i, seg, segLen, into)
      if (closedFmtIndex > i) {
        i = closedFmtIndex
        fmtMatched = true
      }
      if (fmtMatched) continue

      const url1P: RegExp = /\[url=(.*?)\](.*?)\[\/url\]/gi
      url1P.lastIndex = i
      const url1M = url1P.exec(seg)
      if (url1M && url1M.index === i) {
        i = url1P.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.URL
        n.href = url1M[1]
        n.text = escSegHtml(url1M[2])
        into.push(n)
        continue
      }

      const url2P: RegExp = /\[url\](.*?)\[\/url\]/gi
      url2P.lastIndex = i
      const url2M = url2P.exec(seg)
      if (url2M && url2M.index === i) {
        i = url2P.lastIndex
        const n = new BBNode()
        n.type = BBNodeType.URL
        n.href = url2M[1]
        n.text = escSegHtml(url2M[1])
        into.push(n)
        continue
      }

      CLOSE_TAG_PATTERN.lastIndex = i
      const closeM = CLOSE_TAG_PATTERN.exec(seg)
      if (closeM && closeM.index === i) {
        i = CLOSE_TAG_PATTERN.lastIndex
        continue
      }

      pushTextNode(into, '[')
      i++
      continue
    }

    let nextBracket = seg.indexOf('[', i)
    if (nextBracket < 0) nextBracket = segLen
    if (nextBracket > i) {
      pushTextNode(into, seg.substring(i, nextBracket))
      i = nextBracket
    } else {
      pushTextNode(into, seg.substring(i, i + 1))
      i++
    }
  }
}

function checkInlineFormat(startIdx: number, seg: string, segLen: number, into: BBNode[]): number {
  const savedI = startIdx
  let i = startIdx

  const fmtPats: FormatRecord[] = [
    { open: /\[b\]/gi, close: '[/b]', type: BBNodeType.BOLD },
    { open: /\[h\]/gi, close: '[/h]', type: BBNodeType.BOLD },
    { open: /\[item\]/gi, close: '[/item]', type: BBNodeType.BOLD },
    { open: /\[i\]/gi, close: '[/i]', type: BBNodeType.ITALIC },
    { open: /\[u\]/gi, close: '[/u]', type: BBNodeType.UNDERLINE },
    { open: /\[del\]/gi, close: '[/del]', type: BBNodeType.STRIKETHROUGH },
    { open: /\[color=(#[0-9a-fA-F]+|\w+)\]/gi, close: '[/color]', type: BBNodeType.COLOR },
    { open: /\[size=(\d+)\]/gi, close: '[/size]', type: BBNodeType.SIZE },
    { open: /\[font=(.*?)\]/gi, close: '[/font]', type: BBNodeType.FONT },
  ]

  for (let fi = 0; fi < fmtPats.length; fi++) {
    const rec = fmtPats[fi]
    rec.open.lastIndex = i
    const fm = rec.open.exec(seg)
    if (fm && fm.index === i) {
      i = rec.open.lastIndex
      const closeIdx = seg.toLowerCase().indexOf(rec.close.toLowerCase(), i)
      const bodyEnd = closeIdx >= 0 ? closeIdx : segLen
      const body = seg.substring(i, bodyEnd)
      i = closeIdx >= 0 ? bodyEnd + rec.close.length : segLen

      const n = new BBNode()
      n.type = rec.type
      if (rec.type === BBNodeType.COLOR) n.color = fm[1]
      if (rec.type === BBNodeType.SIZE) n.size = parseInt(fm[1], 10)
      if (rec.type === BBNodeType.FONT) n.fontFamily = fm[1]

      const childNodes: BBNode[] = []
      parseInlineInto(body, childNodes)
      if (childNodes.length === 1 && childNodes[0].type === BBNodeType.TEXT) {
        n.text = childNodes[0].text
      } else if (childNodes.length === 0) {
        n.text = ''
      } else {
        n.children = childNodes
      }
      into.push(n)
      return i
    }
  }
  return savedI
}

export { parseBBCode }
