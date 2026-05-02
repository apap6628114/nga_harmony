import type { TopicRaw, ThreadPageInfo, TopicListInfo, Pagination } from '../model/Topic';
import { decodeAnonymousName } from './AnonymousParser';

function hasKeywordMatch(content: string, keywords: string[]): boolean {
  for (let i = 0; i < keywords.length; i++) {
    if (content.includes(keywords[i])) {
      return true
    }
  }
  return false
}

export function parseTopicList(raw: object | null, blacklist: Set<string> = new Set(),
  keywords: string[] = [], currentPage: number = 1): TopicListInfo {
  const topics: ThreadPageInfo[] = [];
  const rawObj = raw as Record<string, Object>;
  const dataObj = rawObj?.['data'] as Record<string, Object> | undefined;
  const tMap = dataObj?.['__T'] as Record<string, Object> ?? {};
  const totalRows = Number(dataObj?.['__ROWS'] ?? 0);
  const rowsPerPage = Number(dataObj?.['__T__ROWS_PAGE'] ?? 35);

  const keys = Object.keys(tMap);
  for (const key of keys) {
    const t = tMap[key] as Record<string, Object>;
    if (!t || !t['tid']) continue;
    if (blacklist.has(String(t['authorid']))) continue;
    if (hasKeywordMatch(String(t['subject'] ?? ''), keywords)) continue;
    topics.push(mapTopicRaw(t));
  }

  const forumInfo = dataObj?.['__F'] as Record<string, Object>;

  return {
    name: String(forumInfo?.['name'] ?? ''),
    threadPageList: topics,
    subBoardList: [],
    curTime: Number(rawObj?.['time'] ?? 0),
    pagination: calcPagination(totalRows, rowsPerPage, currentPage),
  };
}

function mapTopicRaw(raw: Record<string, Object>): ThreadPageInfo {
  const __P = raw['__P'] as Record<string, Object> | undefined;
  const rawAuthor: string = String(raw['author'] ?? '');
  const isAnonymity: boolean = rawAuthor.startsWith('#anony_');
  const author: string = isAnonymity ? decodeAnonymousName(rawAuthor) : rawAuthor;
  return {
    tid: Number(raw['tid']),
    fid: Number(raw['fid']),
    author: author,
    authorId: Number(raw['authorid']),
    lastPoster: String(raw['lastposter'] ?? ''),
    replies: Number(raw['replies'] ?? 0),
    subject: String(raw['subject'] ?? ''),
    titleFont: String(raw['titlefont'] ?? ''),
    type: Number(raw['type'] ?? 0),
    topicMisc: String(raw['topic_misc'] ?? ''),
    page: 0,
    pid: 0,
    position: 0,
    isAnonymity: isAnonymity,
    postDate: Number(raw['postdate'] ?? 0),
    replyInfo: __P ? {
      pidStr: String(__P['pid'] ?? ''),
      content: String(__P['content'] ?? ''),
      subject: String(__P['subject'] ?? ''),
      postDate: String(__P['postdate'] ?? ''),
      authorId: String(__P['authorid'] ?? ''),
      tidStr: String(__P['tid'] ?? ''),
    } : {
      pidStr: '',
      content: '',
      subject: '',
      postDate: '',
      authorId: '',
      tidStr: '',
    },
    board: '',
    mirrorBoard: false,
    previewSnippet: '',
    previewImages: [],
  };
}

export function calcPagination(totalRows: number, rowsPerPage: number, currentPage: number): Pagination {
  return {
    page: currentPage,
    totalPages: Math.ceil(totalRows / rowsPerPage),
    totalRows,
  };
}
