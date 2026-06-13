/**
 * HTML 响应体转 NGA 原始 JSON 结构
 * 输入：NGA read.php 返回的 HTML 页面（GBK->UTF-8 解码后）
 * 输出：与 __output=8 JSON API 相同形状的 { data: { __R, __U, __T, __F, __ROWS } }
 * 可直接喂给 parseThreadData() 使用
 */

import { preprocessJson } from './NgaJsonSanitizer';
import { unescapeHtml } from './_shared/HtmlEntityCodec';

const PROC_MARKER: string = 'commonui.postArg.proc(';
const SETALL_MARKER: string = 'commonui.userInfo.setAll(';
const SETDEFAULT_MARKER: string = 'commonui.postArg.setDefault(';

function extractIntVar(html: string, varName: string, defaultValue: number): number {
  const regex: RegExp = new RegExp(varName + '\\s*=\\s*(\\d+)');
  const match: RegExpExecArray | null = regex.exec(html);
  if (match) {
    return parseInt(match[1], 10);
  }
  return defaultValue;
}

function extractStringVar(html: string, varName: string, defaultValue: string): string {
  const regex: RegExp = new RegExp(varName + '\\s*=\\s*\'([^\']*)\'');
  const match: RegExpExecArray | null = regex.exec(html);
  if (match) {
    return match[1];
  }
  return defaultValue;
}

function extractBalancedBraces(html: string, startPos: number): string {
  let pos: number = startPos;
  while (pos < html.length && (html[pos] === ' ' || html[pos] === '\n' ||
    html[pos] === '\r' || html[pos] === '\t')) {
    pos++;
  }
  if (pos >= html.length || html[pos] !== '{') {
    return '';
  }
  let depth: number = 1;
  const jsonStart: number = pos;
  pos++;
  let inString: boolean = false;
  let stringChar: string = '';
  while (pos < html.length && depth > 0) {
    const ch: string = html[pos];
    if (inString) {
      if (ch === '\\') {
        if (pos + 1 < html.length && (html[pos + 1] === '"' || html[pos + 1] === '\\' ||
          html[pos + 1] === '/' || html[pos + 1] === 'b' ||
          html[pos + 1] === 'f' || html[pos + 1] === 'n' ||
          html[pos + 1] === 'r' || html[pos + 1] === 't')) {
          pos += 2;
          continue;
        }
      }
      if (ch === stringChar) {
        inString = false;
      }
    } else {
      if (ch === '"') {
        inString = true;
        stringChar = ch;
      } else if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
      }
    }
    pos++;
  }
  if (depth !== 0) {
    return '';
  }
  return html.substring(jsonStart, pos);
}

function extractUserInfo(html: string): Record<string, Object> {
  const idx: number = html.indexOf(SETALL_MARKER);
  if (idx < 0) {
    return {};
  }
  const jsonStr: string = extractBalancedBraces(html, idx + SETALL_MARKER.length);
  if (!jsonStr) {
    return {};
  }
  try {
    const cleaned: string = preprocessJson(jsonStr);
    const parsed: Object = JSON.parse(cleaned);
    if (typeof parsed === 'object' && parsed !== null) {
      return parsed as Record<string, Object>;
    }
  } catch (e) {
    return {};
  }
  return {};
}

interface PostArgData {
  lou: number;
  pid: number;
  type: number;
  authorid: string;
  postdatetimestamp: number;
  score: number;
  score_2: number;
  contentLength: number;
  fromClient: string;
  fromClientModel: string;
}

function splitTopLevelArgs(s: string): string[] {
  const args: string[] = [];
  let depth: number = 0;
  let inString: boolean = false;
  let stringChar: string = '';
  let current: string = '';
  for (let i: number = 0; i < s.length; i++) {
    const ch: string = s[i];
    if (inString) {
      current += ch;
      if (ch === '\\') {
        i++;
        if (i < s.length) {
          current += s[i];
        }
      } else if (ch === stringChar) {
        inString = false;
      }
    } else if (ch === "'" || ch === '"') {
      current += ch;
      inString = true;
      stringChar = ch;
    } else if (ch === '(' || ch === '[') {
      current += ch;
      depth++;
    } else if (ch === ')' || ch === ']') {
      current += ch;
      depth--;
    } else if (ch === ',' && depth === 0) {
      args.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  if (current.trim().length > 0) {
    args.push(current.trim());
  }
  return args;
}

function parseAllPostArgs(html: string): Map<number, PostArgData> {
  const result: Map<number, PostArgData> = new Map();
  let searchFrom: number = 0;
  while (true) {
    const startIdx: number = html.indexOf(PROC_MARKER, searchFrom);
    if (startIdx < 0) {
      break;
    }
    const argsStart: number = startIdx + PROC_MARKER.length;
    let pos: number = argsStart;
    let depth: number = 1;
    let inString: boolean = false;
    let stringChar: string = '';
    while (pos < html.length && depth > 0) {
      const ch: string = html[pos];
      if (inString) {
        if (ch === '\\') {
          pos += 2;
          continue;
        }
        if (ch === stringChar) {
          inString = false;
        }
      } else {
        if (ch === "'" || ch === '"') {
          inString = true;
          stringChar = ch;
        } else if (ch === '(') {
          depth++;
        } else if (ch === ')') {
          depth--;
        }
      }
      pos++;
    }
    if (depth !== 0) {
      break;
    }
    const callArgsStr: string = html.substring(argsStart, pos - 1);
    const args: string[] = splitTopLevelArgs(callArgsStr);
    if (args.length >= 21) {
      const data: PostArgData = {
        lou: 0,
        pid: 0,
        type: 0,
        authorid: '',
        postdatetimestamp: 0,
        score: 0,
        score_2: 0,
        contentLength: 0,
        fromClient: '',
        fromClientModel: '',
      };
      const louStr: string = args[0];
      data.lou = parseInt(louStr, 10) || 0;
      const pidStr: string = args[10];
      data.pid = parseInt(pidStr, 10) || 0;
      const typeStr: string = args[11];
      data.type = parseInt(typeStr, 10) || 0;
      const aidStr: string = args[13];
      data.authorid = aidStr.replace(/'/g, '');
      const tsStr: string = args[14];
      data.postdatetimestamp = parseInt(tsStr, 10) || 0;
      const scoreStr: string = args[15];
      const scoreParts: string[] = scoreStr.replace(/'/g, '').split(',');
      data.score_2 = parseInt(scoreParts[0], 10) || 0;
      data.score = parseInt(scoreParts[1], 10) || 0;
      const clStr: string = args[16];
      data.contentLength = parseInt(clStr.replace(/'/g, ''), 10) || 0;
      const fcStr: string = args[19];
      data.fromClient = fcStr.replace(/'/g, '');
      if (args.length > 20) {
        const fcmStr: string = args[20];
        data.fromClientModel = fcmStr.replace(/'/g, '');
      }
      result.set(data.lou, data);
    }
    searchFrom = startIdx + PROC_MARKER.length;
  }
  return result;
}

function extractTagContentById(html: string, idPrefix: string, idSuffix: string,
  tagName: string, endMarker: string): string {
  const marker: string = idPrefix + idSuffix;
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const afterId: number = html.indexOf('>', startIdx);
  if (afterId < 0) {
    return '';
  }
  const contentStart: number = afterId + 1;
  const endIdx: number = html.indexOf(endMarker, contentStart);
  if (endIdx < 0) {
    return '';
  }
  return html.substring(contentStart, endIdx);
}

function extractPostContent(html: string, lou: number): string {
  const marker: string = `id='postcontent${lou}'`;
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const tagEnd: number = html.indexOf('>', startIdx);
  if (tagEnd < 0) {
    return '';
  }
  const contentStart: number = tagEnd + 1;
  const endIdx: number = html.indexOf('</span>', contentStart);
  if (endIdx < 0) {
    return '';
  }
  return unescapeHtml(html.substring(contentStart, endIdx));
}

function extractPostSubject(html: string, lou: number): string {
  const marker: string = `<h3 id='postsubject${lou}'>`;
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const contentStart: number = startIdx + marker.length;
  const endIdx: number = html.indexOf('</h3>', contentStart);
  if (endIdx < 0) {
    return '';
  }
  return unescapeHtml(html.substring(contentStart, endIdx));
}

function extractPostDate(html: string, lou: number): string {
  const marker: string = `<span id='postdate${lou}'`;
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const tagEnd: number = html.indexOf('>', startIdx);
  if (tagEnd < 0) {
    return '';
  }
  const contentStart: number = tagEnd + 1;
  const endIdx: number = html.indexOf('</span>', contentStart);
  if (endIdx < 0) {
    return '';
  }
  return html.substring(contentStart, endIdx).trim();
}

function extractPostAuthorId(html: string, lou: number): string {
  const marker: string = `id='postauthor${lou}'`;
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const before: number = html.lastIndexOf('<a', startIdx);
  if (before < 0) {
    return '';
  }
  const tagContent: string = html.substring(before, startIdx + marker.length);
  const uidMatch: RegExpExecArray | null = /uid=(\d+)/.exec(tagContent);
  if (uidMatch) {
    return uidMatch[1];
  }
  return '';
}

function extractForumName(html: string): string {
  const marker: string = "<h2 id='currentForumName'";
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const tagEnd: number = html.indexOf('>', startIdx);
  if (tagEnd < 0) {
    return '';
  }
  const contentStart: number = tagEnd + 1;
  const endIdx: number = html.indexOf('</h2>', contentStart);
  if (endIdx < 0) {
    return '';
  }
  return html.substring(contentStart, endIdx).trim();
}

function extractThreadSubject(html: string): string {
  const marker: string = "<h1 id='currentTopicName'";
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    return '';
  }
  const tagEnd: number = html.indexOf('>', startIdx);
  if (tagEnd < 0) {
    return '';
  }
  const contentStart: number = tagEnd + 1;
  const endIdx: number = html.indexOf('</h1>', contentStart);
  if (endIdx < 0) {
    return '';
  }
  return html.substring(contentStart, endIdx).trim();
}

function extractPostAuthorName(userInfo: Record<string, Object>, authorid: number): string {
  const uidKey: string = String(authorid);
  const user: Record<string, Object> | undefined = userInfo[uidKey] as Record<string, Object> | undefined;
  if (user && user['username']) {
    return String(user['username']);
  }
  return '';
}

/**
 * 从 commonui.postArg.setDefault(fid,stid,tid,...,totalReplies,lastPostTs,pageSize) 提取总回复数
 * 倒数第 3 个参数 = 全楼总回复数，倒数第 1 个 = 每页帖子数
 */
function extractTotalReplies(html: string): number {
  const idx: number = html.indexOf(SETDEFAULT_MARKER);
  if (idx < 0) {
    return -1;
  }
  const argsStart: number = idx + SETDEFAULT_MARKER.length;
  let pos: number = argsStart;
  let depth: number = 1;
  let inString: boolean = false;
  let stringChar: string = '';
  while (pos < html.length && depth > 0) {
    const ch: string = html[pos];
    if (inString) {
      if (ch === '\\') {
        pos += 2;
        continue;
      }
      if (ch === stringChar) {
        inString = false;
      }
    } else {
      if (ch === "'" || ch === '"') {
        inString = true;
        stringChar = ch;
      } else if (ch === '(') {
        depth++;
      } else if (ch === ')') {
        depth--;
      }
    }
    pos++;
  }
  if (depth !== 0) {
    return -1;
  }
  const argsStr: string = html.substring(argsStart, pos - 1);
  const args: string[] = splitTopLevelArgs(argsStr);
  // 参数格式固定：fid,stid,tid,...,totalReplies,lastPostTs,postsPerPage
  // 倒数第 3 个 = totalReplies, 倒数第 1 个 = postsPerPage(校验用)
  if (args.length >= 3) {
    const val: string = args[args.length - 3].trim();
    const n: number = parseInt(val, 10);
    if (!isNaN(n) && n >= 0) {
      return n;
    }
  }
  return -1;
}

/**
 * 从 HTML 中解析 ubbcode.attach.load() 调用的附件数据（优先方案）
 * 失败时返回 null
 */
function tryParseAttachLoad(html: string, lou: number): Record<string, Object>[] | null {
  const marker: string = `ubbcode.attach.load('postattach${lou}'`;
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) return null;

  const afterMarker: string = html.substring(startIdx + marker.length);
  const contentMarker: string = `'postcontent${lou}'`;
  const contentIdx: number = afterMarker.indexOf(contentMarker);
  if (contentIdx < 0) return null;

  let pos: number = contentIdx + contentMarker.length;
  while (pos < afterMarker.length && (afterMarker[pos] === ',' || afterMarker[pos] === ' ' ||
    afterMarker[pos] === '\n' || afterMarker[pos] === '\r')) {
    pos++;
  }
  if (pos >= afterMarker.length || afterMarker[pos] !== '[') return null;

  let depth: number = 1;
  let inStr: boolean = false;
  let strChar: string = '';
  const jsonStart: number = pos;
  pos++;

  while (pos < afterMarker.length && depth > 0) {
    const ch: string = afterMarker[pos];
    if (inStr) {
      if (ch === '\\') { pos += 2; continue; }
      if (ch === strChar) { inStr = false; }
    } else {
      if (ch === "'" || ch === '"') { inStr = true; strChar = ch; }
      else if (ch === '[') depth++;
      else if (ch === ']') depth--;
    }
    pos++;
  }
  if (depth !== 0) return null;

  const raw: string = afterMarker.substring(jsonStart, pos);
  const attachs: Record<string, Object>[] = [];
  let itemStart: number = raw.indexOf('{');
  let itemIdx: number = 0;

  while (itemStart >= 0) {
    let itemEnd: number = -1;
    let brDepth: number = 0;
    let inStr: boolean = false;
    let strChar: string = '';
    for (let si: number = itemStart; si < raw.length; si++) {
      const sc: string = raw[si];
      if (inStr) {
        if (sc === '\\') { si++; continue; }
        if (sc === strChar) inStr = false;
      } else {
        if (sc === "'" || sc === '"') { inStr = true; strChar = sc; }
        else if (sc === '{') brDepth++;
        else if (sc === '}') { brDepth--; if (brDepth === 0) { itemEnd = si + 1; break; } }
      }
    }
    if (itemEnd < 0) break;

    const itemBody: string = raw.substring(itemStart, itemEnd);
    itemStart = raw.indexOf('{', itemEnd);

    const urlMatch: RegExpExecArray | null = /url\s*:\s*'([^']*)'/i.exec(itemBody);
    const nameMatch: RegExpExecArray | null = /name\s*:\s*'([^']*)'/i.exec(itemBody);
    const typeMatch: RegExpExecArray | null = /type\s*:\s*'([^']*)'/i.exec(itemBody);
    const thumbMatch: RegExpExecArray | null = /thumb\s*:\s*'([^']*)'/i.exec(itemBody);
    const sizeMatch: RegExpExecArray | null = /size\s*:\s*'([^']*)'/i.exec(itemBody);
    const dscpMatch: RegExpExecArray | null = /dscp\s*:\s*'([^']*)'/i.exec(itemBody);
    const orgNameMatch: RegExpExecArray | null = /url_utf8_org_name\s*:\s*'([^']*)'/i.exec(itemBody);
    const aidMatch: RegExpExecArray | null = /aid\s*:\s*'([^']*)'/i.exec(itemBody);

    const url: string = urlMatch ? urlMatch[1] : '';
    const fileExtMatch: RegExpExecArray | null = /\.(\w+)$/.exec(url);
    const fileExt: string = fileExtMatch ? fileExtMatch[1].toLowerCase() : '';

    attachs.push({
      'aid': aidMatch ? aidMatch[1] : '',
      'attachurl': url,
      'url_utf8_org_name': orgNameMatch ? orgNameMatch[1] : '',
      'name': nameMatch ? nameMatch[1] : '',
      'ext': fileExt,
      'type': typeMatch ? typeMatch[1] : 'img',
      'size': Number(sizeMatch ? sizeMatch[1] : '0') || 0,
      'thumb': Number(thumbMatch ? thumbMatch[1] : '0') || 0,
      'dscp': dscpMatch ? dscpMatch[1] : '',
      'subid': itemIdx,
    });
    itemIdx++;
  }

  return attachs.length > 0 ? attachs : null;
}

/**
 * 将 NGA HTML 帖子页面解析为与 __output=8 JSON API 相同形状的对象
 * 返回: { data: { __R, __U, __T, __F, __ROWS, __R__ROWS_PAGE, __PAGE } }
 * 可直接传入 parseThreadData()
 */
export function parseHtmlToRawJson(html: string): object {
  const __U: Record<string, Object> = extractUserInfo(html);
  const postArgs: Map<number, PostArgData> = parseAllPostArgs(html);
  const tid: number = extractIntVar(html, '__CURRENT_TID', 0);
  const fid: number = extractIntVar(html, '__CURRENT_FID', 0);
  const page: number = extractIntVar(html, '__CURRENT_PAGE', 1);
  const pagePosts: number = extractIntVar(html, '__CURRENT_PAGE_POSTS', 20);

  const __R: Record<string, Object> = {};
  let maxLou: number = -1;
  const defaultPostdate: string = '';

  const procKeys: number[] = [];
  postArgs.forEach((_value: PostArgData, key: number): void => {
    procKeys.push(key);
  });
  procKeys.sort((a: number, b: number): number => a - b);

  for (let i: number = 0; i < procKeys.length; i++) {
    const lou: number = procKeys[i];
    const arg: PostArgData | undefined = postArgs.get(lou);
    if (!arg) {
      continue;
    }
    const content: string = extractPostContent(html, lou);
    const subject: string = extractPostSubject(html, lou);
    const dateStr: string = extractPostDate(html, lou);
    const postDate: string = dateStr || defaultPostdate;
    if (lou > maxLou) {
      maxLou = lou;
    }

    let attachs: Record<string, Object>[] = tryParseAttachLoad(html, lou) ?? [];

    const row: Record<string, Object> = {
      'pid': arg.pid as Object,
      'fid': fid as Object,
      'tid': tid as Object,
      'lou': lou as Object,
      'authorid': arg.authorid as Object,
      'author': extractPostAuthorName(__U, parseInt(arg.authorid, 10) || 0) as Object,
      'subject': subject as Object,
      'content': content as Object,
      'postdate': postDate as Object,
      'postdatetimestamp': arg.postdatetimestamp as Object,
      'type': arg.type as Object,
      'score': arg.score as Object,
      'score_2': arg.score_2 as Object,
      'content_length': arg.contentLength as Object,
      'from_client': arg.fromClient as Object,
      'from_client_model': arg.fromClientModel as Object,
      'vote': '' as Object,
      'alterinfo': '' as Object,
      'isanonymous': false as Object,
      'attachs': attachs as Object,
    };

    __R[String(lou)] = row;
  }

  const currentPageRows: number = maxLou + 1;
  const totalReplies: number = extractTotalReplies(html);
  const totalRows: number = totalReplies >= 0 ? totalReplies + 1 : currentPageRows;

  let firstPostDate: string = '';
  let lastPostDate: string = '';
  let firstPostTs: number = 0;
  let lastPostTs: number = 0;
  let firstAuthorId: number = 0;
  let lastAuthorId: number = 0;

  if (procKeys.length > 0) {
    const firstLou: number = procKeys[0];
    const firstArg: PostArgData | undefined = postArgs.get(firstLou);
    if (firstArg) {
      firstPostDate = extractPostDate(html, firstLou);
      firstPostTs = firstArg.postdatetimestamp;
      firstAuthorId = parseInt(firstArg.authorid, 10) || 0;
    }
    const lastLou: number = procKeys[procKeys.length - 1];
    const lastArg: PostArgData | undefined = postArgs.get(lastLou);
    if (lastArg) {
      lastPostDate = extractPostDate(html, lastLou);
      lastPostTs = lastArg.postdatetimestamp;
      lastAuthorId = parseInt(lastArg.authorid, 10) || 0;
    }
  }

  const __T: Record<string, Object> = {
    'tid': tid as Object,
    'fid': fid as Object,
    'subject': extractThreadSubject(html) as Object,
    'replies': Math.max(0, totalRows - 1) as Object,
    'this_visit_rows': currentPageRows as Object,
    'authorid': firstAuthorId as Object,
    'author': extractPostAuthorName(__U, firstAuthorId) as Object,
    'postdate': (firstPostTs || 0) as Object,
    'lastpost': (lastPostTs || 0) as Object,
    'lastposter': extractPostAuthorName(__U, lastAuthorId) as Object,
    'type': 0 as Object,
    'locked': 0 as Object,
    'recommend': 0 as Object,
    'digest': 0 as Object,
  };

  const __F: Record<string, string> = {
    'name': extractForumName(html),
  };

  const data: Record<string, Object> = {
    '__R': __R as Object,
    '__U': __U as Object,
    '__T': __T as Object,
    '__F': __F as Object,
    '__ROWS': totalRows as Object,
    '__R__ROWS_PAGE': pagePosts as Object,
    '__PAGE': page as Object,
  };

  const result: Record<string, Object> = {
    'data': data as Object,
  };

  return result as Object;
}
