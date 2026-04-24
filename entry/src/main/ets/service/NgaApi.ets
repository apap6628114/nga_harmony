/**
 * NGA API 业务逻辑层 - 鸿蒙端
 * 所有返回类型必须使用显式 interface/class
 */

import { ngaClient } from './NgaClient';
import { sessionStore, type Session } from './SessionStore';
import { parseForumCategories } from '../parser/ForumParser';
import { parseTopicList } from '../parser/TopicParser';
import { parseThreadData } from '../parser/ThreadParser';
import { parseNotifications } from '../parser/NotificationParser';
import { parseMessageList, parseMessageDetail } from '../parser/MessageParser';
import { parseNgaError } from '../parser/ErrorParser';
import { parseFromClient } from '../parser/ClientParser';
import { resolveAttachUrl } from './ContentParser';
import type { Category } from '../model/Forum';
import type { ThreadRowInfo, Attachment } from '../model/Thread';
import type { TopicListInfo } from '../model/Topic';
import type { NgaNotification } from '../model/Notification';
import type { MessageListInfo, MessageDetailInfo } from '../model/Message';
import { ProfileData, ReputationData, AdminForumsData } from '../model/User';

// ============== 返回类型定义 ==============

export class ApiResult {
  ok: boolean = false;
  error: string = '';
}

export class CaptchaResult extends ApiResult {
  image: string = '';
}

export class LoginStep1Result extends ApiResult {
  needCaptcha: boolean = false;
  loginToken: string = '';
  captchaId: string = '';
  captchaImage: string = '';
}

export class LoginStep2Result extends ApiResult {
  needCaptcha: boolean = false;
  loginToken: string = '';
  captchaId: string = '';
  captchaImage: string = '';
  token: string = '';
  user: UserInfo | null = null;
}

export class UserInfo {
  uid: string = '';
  nickName: string = '';
  avatarUrl: string = '';
}

export class CategoriesResult extends ApiResult {
  data: Category[] = [];
}

export class TopicListResult extends ApiResult {
  data: TopicListInfo | null = null;
}

export class PostInfo {
  pid: number = 0;
  lou: number = 0;
  authorid: number = 0;
  author: string = '';
  subject: string = '';
  content: string = '';
  postdate: string = '';
  level: string = '';
  yz: string = '';
  avatar: string = '';
  signature: string = '';
  attachs: PostAttachInfo[] = [];
  comments: PostInfo[] = [];
  hotReplies: string[] = [];
  fromClient: string = '';
  from_client_model: string = '';
  isanonymous: boolean = false;
  alterinfo: string = '';
  score: number = 0;
  score_2: number = 0;
  isInBlackList: boolean = false;
  isMuted: boolean = false;
  reputation: number = 0;
  memberGroup: string = '';
  postCount: string = '';
  muteTime: string = '';
}

export class PostAttachInfo {
  aid: string = '';
  attachurl: string = '';
  url_utf8_org_name: string = '';
  name: string = '';
  ext: string = '';
  type: string = '';
  size: number = 0;
  thumb: string = '';
  dscp: string = '';
  subid: number = 0;
}

export class ThreadPagination {
  page: number = 1;
  totalPages: number = 0;
  totalRows: number = 0;
}

export class ThreadResult extends ApiResult {
  threadInfo: object | null = null;
  forumName: string = '';
  pagination: ThreadPagination = new ThreadPagination();
  posts: PostInfo[] = [];
}

export class PostAuthResult extends ApiResult {
  auth: string = '';
  attachUrl: string = '';
  if_moderator: number = 0;
}

export class PostReplyResult extends ApiResult {
  tid: number = 0;
  pid: string = '';
}

export class NotificationsResult extends ApiResult {
  data: NgaNotification[] = [];
}

export class MessageListResult extends ApiResult {
  data: MessageListInfo | null = null;
}

export class MessageDetailResult extends ApiResult {
  data: MessageDetailInfo | null = null;
}

export class MessageSendResult extends ApiResult {
  mid: string = '';
}

export class UserProfileResult extends ApiResult {
  data: ProfileData | null = null;
}

export class DomainResult extends ApiResult {
  domain: string = '';
}

export class CurrentUserResult extends ApiResult {
  user: UserInfo | null = null;
}

export class CheckinResult extends ApiResult {
  data: object | null = null;
}

export class SearchForumResult extends ApiResult {
  data: object | null = null;
}

// ============== 临时登录会话 ==============

interface LoginSession {
  username: string;
  password: string;
  createdAt: number;
}

const loginSessions = new Map<string, LoginSession>();

// ============== 认证 ==============

export async function getCaptcha(captchaId: string): Promise<CaptchaResult> {
  const result = new CaptchaResult();
  try {
    result.image = await ngaClient.getCaptchaV2(captchaId);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取验证码失败';
  }
  return result;
}

export async function loginStep1(username: string, password: string): Promise<LoginStep1Result> {
  const result = new LoginStep1Result();

  if (!username || !password) {
    result.error = '请输入用户名和密码';
    return result;
  }

  const captchaId = `login${Date.now()}${Math.floor(Math.random() * 10000)}`;
  const loginToken = generateLoginToken();

  loginSessions.set(loginToken, { username, password, createdAt: Date.now() });

  try {
    result.captchaImage = await ngaClient.getCaptchaV2(captchaId);
  } catch (e) {
    // 图片获取失败不阻塞
  }

  result.needCaptcha = true;
  result.loginToken = loginToken;
  result.captchaId = captchaId;
  result.ok = true;
  return result;
}

export async function loginStep2(loginToken: string, captchaId: string, captcha: string): Promise<LoginStep2Result> {
  const result = new LoginStep2Result();

  if (!captcha || !captchaId) {
    result.needCaptcha = true;
    result.loginToken = loginToken;
    result.error = '请输入验证码';
    return result;
  }

  const session = loginSessions.get(loginToken);
  if (!session || Date.now() - session.createdAt > 5 * 60 * 1000) {
    result.needCaptcha = true;
    result.error = '登录会话已过期，请重试';
    return result;
  }

  const loginResult = await ngaClient.loginPassword({
    username: session.username,
    password: session.password,
    captchaId,
    captcha,
    type: '',
  });

  if (loginResult.success && loginResult.uid && loginResult.cid) {
    loginSessions.delete(loginToken);

    let nickName = session.username;
    const avatarUrl = `https://img4.nga.178.com/ngabbs/nga_classic/avatar/${loginResult.uid}.png`;

    // 尝试从 cookie 获取昵称
    const extracted = extractNickName(loginResult.setCookies);
    if (extracted) nickName = extracted;

    // 尝试从 NGA 获取昵称
    try {
      const fetched = await fetchNickNameFromNga(loginResult.uid, loginResult.cid, loginResult.uid);
      if (fetched) {
        nickName = fetched.nickName || nickName;
      }
    } catch (e) {
      // 忽略
    }

    const token = await sessionStore.create(loginResult.uid, loginResult.cid, nickName, avatarUrl);
    result.ok = true;
    result.token = token;
    const user = new UserInfo();
    user.uid = loginResult.uid;
    user.nickName = nickName;
    user.avatarUrl = avatarUrl;
    result.user = user;
    return result;
  }

  // 验证码错误，刷新验证码
  const newCaptchaId = `login${Date.now()}${Math.floor(Math.random() * 10000)}`;
  try {
    result.captchaImage = await ngaClient.getCaptchaV2(newCaptchaId);
  } catch (e) {
    // ignore
  }

  result.needCaptcha = true;
  result.loginToken = loginToken;
  result.captchaId = newCaptchaId;
  result.error = loginResult.error || '验证码错误';
  return result;
}

function extractNickName(setCookies: string[]): string {
  for (let i = 0; i < setCookies.length; i++) {
    const match = setCookies[i].match(/ngaPassportUrlencodedUname=([^;]+)/);
    if (match) {
      try {
        return decodeURIComponent(match[1]);
      } catch (e) {
        return '';
      }
    }
  }
  return '';
}

async function fetchNickNameFromNga(uid: string, cid: string, targetUid: string): Promise<UserInfo | null> {
  try {
    const params: Record<string, string> = {
      '__lib': 'ucp', '__act': 'get', 'lite': 'js', 'noprefix': '', 'uid': targetUid,
    };
    const raw = await ngaClient.get('/nuke.php', params, { uid, cid }) as Record<string, Object>;
    const data = raw?.['data'] as Record<string, Object> | undefined;
    const d = (data?.['0'] ?? data) as Record<string, Object> | undefined;
    if (d && d['username']) {
      const user = new UserInfo();
      user.nickName = String(d['username']);
      user.avatarUrl = String(d['avatar'] ?? '');
      return user;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

function generateLoginToken(): string {
  const chars = '0123456789abcdef';
  let result = '';
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// ============== 获取当前用户 ==============

export async function getCurrentUser(token: string): Promise<CurrentUserResult> {
  const result = new CurrentUserResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '会话不存在';
    return result;
  }

  try {
    const params: Record<string, string> = {
      '__lib': 'ucp', '__act': 'get', 'lite': 'js', 'noprefix': '', 'uid': session.uid,
    };
    const raw = await ngaClient.get('/nuke.php', params, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const data = raw?.['data'] as Record<string, Object> | undefined;
    const d = (data?.['0'] ?? data) as Record<string, Object> | undefined;

    const nickName = String(d?.['username'] ?? session.nickName);
    const avatarUrl = String(d?.['avatar'] ?? session.avatarUrl);

    await sessionStore.update(token, nickName, avatarUrl);

    const user = new UserInfo();
    user.uid = session.uid;
    user.nickName = nickName;
    user.avatarUrl = avatarUrl;
    result.ok = true;
    result.user = user;
  } catch (e) {
    const user = new UserInfo();
    user.uid = session.uid;
    user.nickName = session.nickName;
    user.avatarUrl = session.avatarUrl;
    result.ok = true;
    result.user = user;
  }
  return result;
}

export async function logout(token: string): Promise<void> {
  await sessionStore.destroy(token);
}

export function getSession(token: string): Session | null {
  return sessionStore.get(token);
}

// ============== 版块 ==============

export async function getForumCategories(token: string): Promise<CategoriesResult> {
  const result = new CategoriesResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    const params: Record<string, string> = { '__lib': 'home', '__act': 'category' };
    const raw = await ngaClient.get('/app_api.php', params, { uid: session.uid, cid: session.cid });
    result.data = parseForumCategories(raw as object);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取板块分类失败';
  }
  return result;
}

export async function searchForum(token: string, key: string): Promise<SearchForumResult> {
  const result = new SearchForumResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    const params: Record<string, string> = { '__output': '8', 'key': key };
    result.data = await ngaClient.getWithBaseUrl('/forum.php', params, 'http://bbs.nga.cn', { uid: session.uid, cid: session.cid });
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '搜索失败';
  }
  return result;
}

// ============== 帖子列表 ==============

export interface TopicListParams {
  fid: string;
  stid: string;
  page: string;
  key: string;
  author: string;
  authorid: string;
  favor: string;
  recommend: string;
  twentyfour: string;
  searchpost: string;
  content: string;
  fidgroup: string;
}

export function createTopicListParams(): TopicListParams {
  return {
    fid: '', stid: '', page: '1', key: '', author: '', authorid: '',
    favor: '', recommend: '', twentyfour: '', searchpost: '', content: '', fidgroup: '',
  };
}

function extractSnippet(content: string): string {
  let text = content;
  text = text.replace(/\[img\][^\[]*\[\/img\]/gi, '');
  text = text.replace(/\[\/?(?:pid|uid|tid|quote|collapse|code|b|i|u|del|h|item|l|r|color|size|font|url|list|align|table|tr|td|style|collapse|flash|lessernuke|album|hip|comment|randomblock|dice|s)\d*[^\]]*\]/gi, '');
  text = text.replace(/\[@\d+\]/g, '');
  text = text.replace(/Post by [^\n]*/gi, '');
  text = text.replace(/\[s:\w+:\w+\]/g, '');
  text = text.replace(/\.?\/mon_\S+\.(?:jpg|jpeg|png|gif|webp|bmp)/gi, '');
  text = text.replace(/https?:\/\/\S+\.(?:jpg|jpeg|png|gif|webp|bmp)\S*/gi, '');
  text = text.replace(/<[^>]+>/g, '');
  text = text.replace(/&\w+;/g, ' ');
  text = text.replace(/\s+/g, ' ').trim();
  return text.slice(0, 150);
}

export async function getTopicList(token: string, params: TopicListParams,
  blacklist: Set<string> = new Set()): Promise<TopicListResult> {
  const result = new TopicListResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    const ngaParams: Record<string, string> = {
      'page': params.page || '1',
      'lite': 'js',
      'noprefix': '',
    };

    if (params.authorid) ngaParams['authorid'] = params.authorid;
    if (params.searchpost) ngaParams['searchpost'] = params.searchpost;
    if (params.favor) ngaParams['favor'] = params.favor;
    if (params.content) ngaParams['content'] = params.content;

    if (params.author) {
      ngaParams['author'] = params.author;
    } else {
      if (params.stid) ngaParams['stid'] = params.stid;
      else if (params.fid && params.fid !== '-1') ngaParams['fid'] = params.fid;
      if (params.key) ngaParams['key'] = params.key;
      if (params.fidgroup) ngaParams['fidgroup'] = params.fidgroup;
    }

    if (params.twentyfour) ngaParams['twentyfour'] = params.twentyfour;
    if (params.recommend) {
      ngaParams['recommend'] = params.recommend;
      ngaParams['order_by'] = 'postdatedesc';
      ngaParams['user'] = '1';
    }

    const raw = await ngaClient.get('/thread.php', ngaParams, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const error = parseNgaError(raw);
    if (error) {
      result.error = error;
      return result;
    }

    const dataObj = raw?.['data'] as Record<string, Object> | undefined;
    const page = Number(dataObj?.['__PAGE'] ?? params.page ?? 1);
    result.data = parseTopicList(raw, blacklist, page);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取主题列表失败';
  }
  return result;
}

// ============== 帖子详情 ==============

export async function getThread(token: string, tid: string, pid: string,
  authorid: string, page: string,
  blacklist: Set<string> = new Set()): Promise<ThreadResult> {
  const result = new ThreadResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    if (!tid && !pid) {
      result.error = '缺少 tid 或 pid';
      return result;
    }

    const ngaParams: Record<string, string> = {
      'page': page || '1',
      '__output': '8',
      'noprefix': '',
      'v2': '',
    };
    if (tid) ngaParams['tid'] = tid;
    if (pid) ngaParams['pid'] = pid;
    if (authorid) ngaParams['authorid'] = authorid;

    const raw = await ngaClient.get('/read.php', ngaParams, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const error = parseNgaError(raw);
    if (error) {
      result.error = error;
      return result;
    }

    const data = parseThreadData(raw, blacklist);
    const dataObj = raw?.['data'] as Record<string, Object> | undefined;

    if (dataObj?.['__PAGE']) {
      data.pagination.page = Number(dataObj['__PAGE']);
    }

    const __U = (dataObj?.['__U'] ?? {}) as Record<string, Object>;
    const forumInfo = data.__F as Record<string, string>;
    result.forumName = forumInfo?.['name'] ?? '';

    const mapRowToPost = (row: ThreadRowInfo): PostInfo => {
      const userInfo = __U[String(row.authorid)] as Record<string, Object> | undefined;
      const post = new PostInfo();
      post.pid = row.pid;
      post.lou = row.lou;
      post.authorid = row.authorid;
      post.author = String(userInfo?.['username'] ?? row.author ?? '');
      post.subject = row.subject;
      post.content = row.content;
      post.postdate = row.postdate;
      post.level = String(userInfo?.['level'] ?? row.level ?? '');
      post.yz = row.yz;
      post.avatar = String(userInfo?.['avatar'] ?? row.js_escap_avatar ?? '');
      post.signature = String(userInfo?.['signature'] ?? row.signature ?? '');
      post.attachs = row.attachs.map((a: Attachment): PostAttachInfo => {
        const info = new PostAttachInfo();
        info.aid = a.aid;
        info.attachurl = resolveAttachUrl(a.attachurl);
        info.url_utf8_org_name = a.url_utf8_org_name;
        info.name = a.name;
        info.ext = a.ext;
        info.type = a.type;
        info.size = a.size;
        info.thumb = a.thumb ? resolveAttachUrl(a.thumb) : '';
        info.dscp = a.dscp;
        info.subid = a.subid;
        return info;
      });
      post.comments = row.comments.map(mapRowToPost);
      post.hotReplies = row.hotReplies;
      post.fromClient = parseFromClient(row.from_client);
      post.from_client_model = row.from_client_model;
      post.isanonymous = row.isanonymous;
      post.alterinfo = row.alterinfo;
      post.score = row.score;
      post.score_2 = row.score_2;
      post.isInBlackList = row.isInBlackList;
      post.isMuted = row.isMuted;
      post.reputation = Number(userInfo?.['reputation'] ?? row.reputation ?? 0);
      post.memberGroup = String(userInfo?.['__groupName'] ?? row.memberGroup ?? '');
      post.postCount = String(userInfo?.['postCount'] ?? row.postCount ?? '');
      post.muteTime = row.muteTime;
      return post;
    };

    result.posts = data.rowList.map(mapRowToPost);

    // 提取 threadInfo
    if (dataObj?.['__T']) {
      const __T = dataObj['__T'] as Record<string, Object>;
      if (__T['tid']) {
        result.threadInfo = __T;
      } else {
        const tKeys = Object.keys(__T);
        if (tKeys.length > 0) {
          const first = __T[tKeys[0]] as Record<string, Object> | undefined;
          if (first && typeof first === 'object' && first['tid']) {
            result.threadInfo = first;
          }
        }
      }
    }

    result.pagination = new ThreadPagination();
    result.pagination.page = data.pagination.page;
    result.pagination.totalPages = data.pagination.totalPages;
    result.pagination.totalRows = data.pagination.totalRows;
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取帖子详情失败';
  }
  return result;
}

// ============== 发帖/回帖 ==============

export async function getPostAuth(token: string, fid: number, action: string,
  tid: number, pid: number, comment: number): Promise<PostAuthResult> {
  const result = new PostAuthResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    const qs: string[] = [`fid=${fid}`, 'lite=js'];
    if (action) qs.push(`action=${action}`);
    if (pid) qs.push(`pid=${pid}`);
    if (tid) qs.push(`tid=${tid}`);
    if (comment) qs.push(`comment=${comment}`);

    const emptyBody: Record<string, string> = {};
    const raw = await ngaClient.post(`/post.php?${qs.join('&')}`, emptyBody, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const dataObj = raw?.['data'] as Record<string, Object> | undefined;
    result.auth = String(dataObj?.['auth'] ?? '');
    result.attachUrl = String(dataObj?.['attach_url'] ?? '');
    result.if_moderator = Number(dataObj?.['if_moderator'] ?? 0);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取auth失败';
  }
  return result;
}

export async function postReply(token: string, tid: number, fid: number,
  content: string, anony: number, attachments: string, attachmentsCheck: string,
  stid: number, action: string, pid: number, postSubject: string): Promise<PostReplyResult> {
  const result = new PostReplyResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    const fields: Record<string, string> = {
      'step': '2',
      'action': action || 'reply',
      'fid': String(fid),
      'post_content': content,
      'anony': String(anony),
      'attachments': attachments,
      'attachments_check': attachmentsCheck,
      '__output': '8',
    };
    if (tid) fields['tid'] = String(tid);
    if (pid) fields['pid'] = String(pid);
    if (postSubject) fields['post_subject'] = postSubject;
    if (stid) fields['stid'] = String(stid);

    const raw = await ngaClient.post('/post.php', fields, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const error = parseNgaError(raw);
    if (error) {
      result.error = error;
      return result;
    }
    const dataObj = raw?.['data'] as Record<string, Object> | undefined;
    result.tid = Number(dataObj?.['tid'] ?? tid ?? 0);
    result.pid = String(dataObj?.['pid'] ?? '');
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '回复失败';
  }
  return result;
}

// ============== 收藏 ==============

export interface FavBoardItem {
  fid: number
  stid: number
  name: string
}

export class ForumFavoritesResult extends ApiResult {
  data: FavBoardItem[] = []
}

export async function fetchForumFavorites(token: string): Promise<ForumFavoritesResult> {
  const result = new ForumFavoritesResult()
  const session = sessionStore.get(token)
  if (!session) {
    result.error = '未登录'
    return result
  }
  try {
    const fields: Record<string, string> = {
      '__lib': 'forum_favor2',
      '__act': 'forum_favor',
      '__output': '8',
      'action': 'sync',
    }
    const raw = await ngaClient.post('/nuke.php', fields, { uid: session.uid, cid: session.cid }) as Record<string, Object>
    const data = raw?.['data'] as Record<string, Object> | undefined
    const items = data?.['0'] as Record<string, Object> | undefined
    if (items && typeof items === 'object') {
      const keys = Object.keys(items)
      const forums: FavBoardItem[] = []
      for (const key of keys) {
        const item = items[key] as Record<string, Object>
        forums.push({
          fid: Number(item['fid']) || 0,
          stid: Number(item['id']) || 0,
          name: String(item['name'] ?? ''),
        })
      }
      result.data = forums
    }
    result.ok = true
  } catch (e) {
    result.error = (e as Error).message ?? '获取收藏板块失败'
  }
  return result
}

export async function addFavorite(token: string, tid: number, pid: number): Promise<ApiResult> {
  const result = new ApiResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const qs: string[] = ['__lib=topic_favor', '__act=topic_favor', 'lite=js', 'action=add', `tid=${tid}`];
    if (pid) qs.push(`pid=${pid}`);
    const emptyBody: Record<string, string> = {};
    await ngaClient.post(`/nuke.php?${qs.join('&')}&noprefix`, emptyBody, { uid: session.uid, cid: session.cid });
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '收藏失败';
  }
  return result;
}

export async function removeFavorite(token: string, tid: number, pid: number, page: number): Promise<ApiResult> {
  const result = new ApiResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const fields: Record<string, string> = {
      '__lib': 'topic_favor',
      '__act': 'topic_favor',
      '__output': '8',
      'action': 'del',
      'page': String(page || 1),
      'tidarray': pid ? `${tid}_${pid}` : String(tid),
    };
    await ngaClient.post('/nuke.php', fields, { uid: session.uid, cid: session.cid });
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '取消收藏失败';
  }
  return result;
}

// ============== 签到 ==============

export async function checkin(token: string): Promise<CheckinResult> {
  const result = new CheckinResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const fields: Record<string, string> = { '__lib': 'check_in', '__act': 'check_in', 'lite': 'js' };
    const raw = await ngaClient.post('/nuke.php', fields, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const error = parseNgaError(raw);
    if (error) {
      result.error = error;
      return result;
    }
    result.data = raw?.['data'] ?? null;
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '签到失败';
  }
  return result;
}

// ============== 通知 ==============

export async function getNotifications(token: string): Promise<NotificationsResult> {
  const result = new NotificationsResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const params: Record<string, string> = {
      '__lib': 'noti', '__output': '8', '__act': 'get_all', 'raw': '3', 'time_limit': '1',
    };
    const raw = await ngaClient.get('/nuke.php', params, { uid: session.uid, cid: session.cid });
    result.data = parseNotifications(raw as object);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取通知失败';
  }
  return result;
}

export async function clearNotifications(token: string): Promise<ApiResult> {
  const result = new ApiResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const emptyBody: Record<string, string> = {};
    await ngaClient.post('/nuke.php?__lib=noti&raw=3&__act=del', emptyBody, { uid: session.uid, cid: session.cid });
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '清除通知失败';
  }
  return result;
}

// ============== 私信 ==============

export async function getMessageList(token: string, page: string): Promise<MessageListResult> {
  const result = new MessageListResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const params: Record<string, string> = {
      '__lib': 'message', '__act': 'message', 'act': 'list', 'page': page || '1', 'lite': 'js',
    };
    const raw = await ngaClient.get('/nuke.php', params, { uid: session.uid, cid: session.cid });
    result.data = parseMessageList(raw as object);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取私信列表失败';
  }
  return result;
}

export async function getMessageDetail(token: string, mid: string, page: string): Promise<MessageDetailResult> {
  const result = new MessageDetailResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    const params: Record<string, string> = {
      '__lib': 'message', '__act': 'message', 'act': 'read', 'page': page || '1', 'mid': mid, 'lite': 'js',
    };
    const raw = await ngaClient.get('/nuke.php', params, { uid: session.uid, cid: session.cid });
    result.data = parseMessageDetail(raw as object);
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取私信详情失败';
  }
  return result;
}

export async function sendMessage(token: string, to: string, mid: string,
  subject: string, content: string): Promise<MessageSendResult> {
  const result = new MessageSendResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }
  try {
    if (!content) {
      result.error = '内容不能为空';
      return result;
    }
    const fields: Record<string, string> = {
      '__lib': 'message',
      '__act': 'message',
      'lite': 'js',
      'act': mid ? 'reply' : 'new',
      'content': content,
    };
    if (to) fields['to'] = to;
    if (mid) fields['mid'] = mid;
    if (subject) fields['subject'] = subject;

    const raw = await ngaClient.post('/nuke.php', fields, { uid: session.uid, cid: session.cid }) as Record<string, Object>;
    const error = parseNgaError(raw);
    if (error) {
      result.error = error;
      return result;
    }
    const dataObj = raw?.['data'] as Record<string, Object> | undefined;
    result.mid = String(dataObj?.['mid'] ?? mid ?? '');
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '发送私信失败';
  }
  return result;
}

// ============== 用户资料 ==============

export async function getUserProfile(token: string, uid: string): Promise<UserProfileResult> {
  const result = new UserProfileResult();
  const session = sessionStore.get(token);
  if (!session) {
    result.error = '未登录';
    return result;
  }

  try {
    const params: Record<string, string> = {
      '__lib': 'ucp', '__act': 'get', 'lite': 'js', 'noprefix': '', 'uid': uid,
    };
    const extraHeaders: Record<string, string> = {
      'Referer': `https://bbs.nga.cn/nuke.php?func=ucp&lite=jsx&uid=${uid}`,
    };
    const raw = await ngaClient.get('/nuke.php', params, { uid: session.uid, cid: session.cid }, extraHeaders) as Record<string, Object>;

    const errorObj = raw?.['error'];
    if (errorObj) {
      const errMsg = typeof errorObj === 'string' ? String(errorObj) :
        String((errorObj as Record<string, Object>)['0']);
      result.error = errMsg || '获取用户资料失败';
      return result;
    }

    const rawInner = (raw?.['data'] ?? {}) as Record<string, Object>;
    const d = (rawInner['0'] ?? rawInner) as Record<string, Object>;
    const regTimestamp = Number(d['regdate']) || 0;
    const muteTime = Number(d['muteTime']) || 0;
    const medalStr = String(d['medal'] ?? '0');
    const hasMedal = medalStr !== '0' && medalStr !== '';

    const repList: ReputationData[] = [];
    if (d['reputation'] && typeof d['reputation'] === 'object') {
      const repObj = d['reputation'] as Record<string, Object>;
      const repKeys = Object.keys(repObj);
      for (let i = 0; i < repKeys.length; i++) {
        const entry = repObj[repKeys[i]];
        if (Array.isArray(entry)) {
          const arr = entry as Object[];
          const repItem = new ReputationData();
          repItem.name = String(arr[0] ?? '');
          repItem.value = String(arr[1] ?? '');
          repItem.reputation = Number(arr[2] ?? 0);
          repItem.topicSubject = String(arr[3] ?? '');
          repItem.postContent = String(arr[4] ?? '');
          repItem.author = String(arr[5] ?? '');
          repItem.time = Number(arr[6] ?? 0);
          repList.push(repItem);
        }
      }
    }

    const adminList: AdminForumsData[] = [];
    if (d['adminForums'] && typeof d['adminForums'] === 'object') {
      const forums = d['adminForums'] as Record<string, Object>;
      const fKeys = Object.keys(forums);
      for (let i = 0; i < fKeys.length; i++) {
        const name = forums[fKeys[i]];
        if (typeof name === 'string') {
          const item = new AdminForumsData();
          item.fid = fKeys[i];
          item.forumName = String(name);
          adminList.push(item);
        }
      }
    }

    const profile = new ProfileData();
    profile.uid = String(d['uid'] ?? uid);
    profile.userName = String(d['username'] ?? '');
    profile.avatarUrl = String(d['avatar'] ?? '');
    profile.group = String(d['group'] ?? '');
    profile.title = String(d['title'] ?? '');
    profile.honor = String(d['honor'] ?? '');
    profile.yz = Number(d['yz'] ?? 0);
    profile.money = String(d['money'] ?? '');
    profile.fame = String(d['fame'] ?? '');
    profile.rvrc = String(d['rvrc'] ?? '');
    profile.posts = String(d['posts'] ?? '');
    profile.regdate = regTimestamp > 0 ? String(regTimestamp) : '';
    profile.sign = String(d['sign'] ?? '');
    profile.ipLoc = String(d['ipLoc'] ?? '');
    profile.medal = hasMedal ? medalStr : '';
    profile.muteTime = muteTime > 0 ? new Date(muteTime * 1000).toISOString().slice(0, 16) : '';
    profile.followByNum = String(d['follow_by_num'] ?? '');
    profile.adminForums = adminList;
    profile.reputationEntryList = repList;

    result.data = profile;
    result.ok = true;
  } catch (e) {
    result.error = (e as Error).message ?? '获取用户资料失败';
  }
  return result;
}

// ============== 域名切换 ==============

export function setDomain(index: number): DomainResult {
  const result = new DomainResult();
  const domains = ngaClient.getDomainList();
  if (index < 0 || index >= domains.length) {
    result.error = '无效域名索引';
    return result;
  }
  ngaClient.setActiveDomainIndex(index);
  result.domain = domains[index];
  result.ok = true;
  return result;
}
