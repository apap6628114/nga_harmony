/**
 * Cookie 工具集 - 解析 set-cookie 响应头。
 * 从 NGA 登录响应的 set-cookie 列表中提取会话凭据。
 */

/**
 * NGA 会话凭据：passport uid 与 cid。
 * 从登录 set-cookie 头解析得到，用于后续所有受保护请求的 Cookie 注入。
 */
export class SessionCookie {
  /** 用户 uid（ngaPassportUid） */
  uid: string = '';
  /** 会话 cid（ngaPassportCid） */
  cid: string = '';
}

/**
 * 从 set-cookie 头列表中解析 NGA 会话凭据（uid + cid）。
 * 同时支持数组形式与单字符串形式（兼容不同 HTTP 实现）。
 * @param setCookieHeader - set-cookie 头原始值，可能为字符串数组或单字符串
 * @returns 解析得到的 SessionCookie（未命中字段为空串）
 */
export function parseSessionCookies(setCookieHeader: string | string[] | undefined): SessionCookie {
  const cookies: string[] = [];
  if (Array.isArray(setCookieHeader)) {
    for (let i = 0; i < (setCookieHeader as string[]).length; i++) {
      cookies.push((setCookieHeader as string[])[i]);
    }
  } else if (typeof setCookieHeader === 'string') {
    cookies.push(setCookieHeader as string);
  }

  const result = new SessionCookie();
  for (let i = 0; i < cookies.length; i++) {
    const c = cookies[i];
    const uidMatch = c.match(/ngaPassportUid=(\d+)/);
    const cidMatch = c.match(/ngaPassportCid=([^;]+)/);
    if (uidMatch) result.uid = uidMatch[1];
    if (cidMatch) result.cid = cidMatch[1];
  }
  return result;
}

/**
 * 将 set-cookie 头归一化为字符串数组。
 * 用于需要回传原始 cookie 列表的场景（如昵称提取）。
 * @param setCookieHeader - set-cookie 头原始值
 * @returns cookie 字符串数组
 */
export function normalizeCookieList(setCookieHeader: string | string[] | undefined): string[] {
  const cookies: string[] = [];
  if (Array.isArray(setCookieHeader)) {
    for (let i = 0; i < (setCookieHeader as string[]).length; i++) {
      cookies.push((setCookieHeader as string[])[i]);
    }
  } else if (typeof setCookieHeader === 'string') {
    cookies.push(setCookieHeader as string);
  }
  return cookies;
}
