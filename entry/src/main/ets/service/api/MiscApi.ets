/**
 * NGA 域名切换 API
 */

import { ngaClient } from '../NgaClient';
import { DomainResult } from '../../model/NgaApiResults';

/**
 * 切换当前激活的 NGA 域名索引
 */
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

/**
 * 获取当前激活的 NGA 域名（含协议）。
 * 供页面/通用工具拼接分享链接、注入 WebView 等使用，避免越层访问 NgaClient。
 * @returns 当前激活域名，如 `https://bbs.nga.cn`
 */
export function getActiveDomain(): string {
  return ngaClient.getActiveDomain();
}
