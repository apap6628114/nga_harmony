/**
 * URL 工具集 - 纯函数，无副作用。
 * 提供主机名提取与查询字符串拼接。
 */

/**
 * 从 URL 中提取主机名（含端口）。
 * 例如 `https://bbs.nga.cn:8080/path` → `bbs.nga.cn:8080`。
 * 无法匹配时原样返回。
 * @param url - 完整 URL
 * @returns 主机名部分
 */
export function extractHostname(url: string): string {
  const match = url.match(/^https?:\/\/([^/]+)/);
  return match ? match[1] : url;
}

/**
 * 基于 baseUrl、path、查询参数构造完整 URL。
 * 当 path 已包含查询串时追加 `&`，否则追加 `?`。
 * 空值参数会被跳过。
 * @param baseUrl - 协议+主机，如 `https://bbs.nga.cn`
 * @param path - 路径，可含已有查询串
 * @param params - 查询参数映射
 * @returns 拼接后的完整 URL
 */
export function buildUrl(baseUrl: string, path: string, params: Record<string, string>): string {
  let url = `${baseUrl}${path}`;
  const qs: string[] = [];
  const keys = Object.keys(params);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    const val = params[key];
    if (val !== undefined && val !== '') {
      qs.push(`${encodeURIComponent(key)}=${encodeURIComponent(val)}`);
    }
  }
  if (qs.length > 0) {
    const hasQuery = path.indexOf('?') >= 0;
    url += (hasQuery ? '&' : '?') + qs.join('&');
  }
  return url;
}
