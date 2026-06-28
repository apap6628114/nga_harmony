import { http } from '@kit.NetworkKit';
import { LruCache } from '../cache/LruCache';
import { RequestQueue } from '../concurrency/RequestQueue';
import { Logger, DOMAIN_MEDIA } from '../utils/Logger';

const logger = new Logger(DOMAIN_MEDIA, 'ImageSizeUtil');

export class ImageSize {
  width: number = 0;
  height: number = 0;
}

const cache: LruCache<ImageSize> = new LruCache<ImageSize>(500);
const pending: Map<string, Promise<ImageSize | null>> = new Map();

/** 图片尺寸预取并发上限 */
const MAX_CONCURRENT: number = 6;
const queue: RequestQueue = new RequestQueue(MAX_CONCURRENT);

function getJpegSize(buf: ArrayBuffer): ImageSize | null {
  const dv: DataView = new DataView(buf);
  if (dv.getUint8(0) !== 0xFF || dv.getUint8(1) !== 0xD8) return null;
  let offset: number = 2;
  while (offset < dv.byteLength - 1) {
    if (dv.getUint8(offset) !== 0xFF) break;
    const marker: number = dv.getUint8(offset + 1);
    if (marker === 0x00) {
      offset += 2;
      continue;
    }
    if (marker >= 0xD0 && marker <= 0xD7) {
      offset += 2;
      continue;
    }
    if (marker === 0xD9 || marker === 0xDA) break;
    if (offset + 4 > dv.byteLength) break;
    if (marker >= 0xC0 && marker <= 0xC3) {
      if (offset + 9 > dv.byteLength) break;
      const h: number = dv.getUint16(offset + 5);
      const w: number = dv.getUint16(offset + 7);
      if (w > 0 && h > 0) {
        const s: ImageSize = new ImageSize();
        s.width = w;
        s.height = h;
        return s;
      }
    }
    const len: number = dv.getUint16(offset + 2);
    offset += len + 2;
  }
  return null;
}

function getPngSize(buf: ArrayBuffer): ImageSize | null {
  const dv: DataView = new DataView(buf);
  if (dv.byteLength < 24) return null;
  if (dv.getUint32(0) !== 0x89504E47) return null;
  const s: ImageSize = new ImageSize();
  s.width = dv.getUint32(16);
  s.height = dv.getUint32(20);
  return s;
}

function getGifSize(buf: ArrayBuffer): ImageSize | null {
  const dv: DataView = new DataView(buf);
  if (dv.byteLength < 10) return null;
  if (dv.getUint32(0) !== 0x47494638) return null;
  const s: ImageSize = new ImageSize();
  s.width = dv.getUint16(6, true);
  s.height = dv.getUint16(8, true);
  return s;
}

function getWebpSize(buf: ArrayBuffer): ImageSize | null {
  const dv: DataView = new DataView(buf);
  if (dv.byteLength < 30) return null;
  if (dv.getUint32(0) !== 0x52494646) return null;
  if (dv.getUint32(8) !== 0x57454250) return null;
  if (dv.getUint32(12) === 0x56503820) {
    const w: number = dv.getUint16(26, true) & 0x3FFF;
    const h: number = dv.getUint16(28, true) & 0x3FFF;
    if (w > 0 && h > 0) {
      const s: ImageSize = new ImageSize();
      s.width = w;
      s.height = h;
      return s;
    }
  }
  if (dv.getUint32(12) === 0x5650384C) {
    const bits: number = dv.getUint32(21, true);
    const w: number = (bits & 0x3FFF) + 1;
    const h: number = ((bits >> 14) & 0x3FFF) + 1;
    if (w > 0 && h > 0) {
      const s: ImageSize = new ImageSize();
      s.width = w;
      s.height = h;
      return s;
    }
  }
  return null;
}

function extractExt(url: string): string {
  const qpos: number = url.indexOf('?');
  const clean: string = qpos >= 0 ? url.substring(0, qpos) : url;
  const dot: number = clean.lastIndexOf('.');
  if (dot < 0) return '';
  return clean.substring(dot + 1);
}

function parseBuf(buf: ArrayBuffer, ext: string): ImageSize | null {
  const lo: string = ext.toLowerCase();
  if (lo === 'jpg' || lo === 'jpeg') return getJpegSize(buf);
  if (lo === 'png') return getPngSize(buf);
  if (lo === 'gif') return getGifSize(buf);
  if (lo === 'webp') return getWebpSize(buf);
  let s: ImageSize | null = getJpegSize(buf);
  if (s) return s;
  s = getPngSize(buf);
  if (s) return s;
  s = getGifSize(buf);
  if (s) return s;
  return getWebpSize(buf);
}

const noRangeHosts: Set<string> = new Set();

function extractHost(url: string): string {
  const start: number = url.indexOf('://');
  if (start < 0) return url;
  const afterProto: string = url.substring(start + 3);
  const slash: number = afterProto.indexOf('/');
  if (slash < 0) return afterProto;
  return afterProto.substring(0, slash);
}

async function doFetchRequest(url: string): Promise<ImageSize | null> {
  const host: string = extractHost(url);
  if (noRangeHosts.has(host)) return null;
  let httpRequest: http.HttpRequest | null = null;
  try {
    httpRequest = http.createHttp();
    const resp: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Range': 'bytes=0-2048' },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 5000,
      readTimeout: 5000,
    });
    const code: number = resp.responseCode;
    if (code !== 206 && code !== 200) return null;
    const buf: ArrayBuffer = resp.result as ArrayBuffer;
    const hdrs: Record<string, string> = resp.header as Record<string, string>
    const contentRange: string = hdrs['content-range'] ?? hdrs['Content-Range'] ?? hdrs['CONTENT-RANGE'] ?? ''
    const contentLen: string = hdrs['content-length'] ?? hdrs['Content-Length'] ?? hdrs['CONTENT-LENGTH'] ?? ''
    logger.verbose('[ImageSize] url=%{public}s code=%{public}d actualBytes=%{public}d Content-Range=%{public}s Content-Length=%{public}s',
      url, code, buf.byteLength, contentRange, contentLen)
    if (code === 200) {
      noRangeHosts.add(host);
      logger.verbose('[ImageSize] Server does not support Range, full image downloaded: host=%{public}s size=%{public}d',
        host, buf.byteLength);
      return null;
    }
    if (buf.byteLength < 4) return null;
    const size: ImageSize | null = parseBuf(buf, extractExt(url));
    if (size) {
      cache.set(url, size);
    }
    return size;
  } catch (e) {
    return null;
  } finally {
    if (httpRequest) {
      httpRequest.destroy();
    }
  }
}

function doFetch(url: string): Promise<ImageSize | null> {
  return new Promise<ImageSize | null>((resolve: (value: ImageSize | null) => void) => {
    queue.schedule(() => {
      doFetchRequest(url).then((result: ImageSize | null) => {
        resolve(result);
        queue.done();
      }, () => {
        resolve(null);
        queue.done();
      });
    });
  });
}

export function getCachedImageSize(url: string): ImageSize | null {
  const r: ImageSize | undefined = cache.get(url);
  if (r) {
    return r;
  }
  return null;
}

export async function fetchImageSize(url: string): Promise<ImageSize | null> {
  const cached: ImageSize | null = getCachedImageSize(url);
  if (cached) return cached;
  const p: Promise<ImageSize | null> | undefined = pending.get(url);
  if (p) return p;
  const promise: Promise<ImageSize | null> = doFetch(url);
  pending.set(url, promise);
  const result: ImageSize | null = await promise;
  pending.delete(url);
  return result;
}
