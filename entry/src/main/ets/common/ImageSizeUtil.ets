import { http } from '@kit.NetworkKit';

export class ImageSize {
  width: number = 0;
  height: number = 0;
}

const cache: Map<string, ImageSize> = new Map();
const pending: Map<string, Promise<ImageSize | null>> = new Map();

function getJpegSize(buf: ArrayBuffer): ImageSize | null {
  const dv: DataView = new DataView(buf);
  let offset: number = 2;
  while (offset < dv.byteLength - 1) {
    if (dv.getUint8(offset) === 0xFF) {
      const marker: number = dv.getUint8(offset + 1);
      if (marker >= 0xC0 && marker <= 0xC3) {
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
    } else {
      break;
    }
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

async function doFetch(url: string): Promise<ImageSize | null> {
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

export function getCachedImageSize(url: string): ImageSize | null {
  const r: ImageSize | undefined = cache.get(url);
  if (r) return r;
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
