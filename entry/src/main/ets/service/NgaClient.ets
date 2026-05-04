import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { preprocessJson } from '../parser/JsonUtil';
import { ngaThrottler } from './Throttle';

// ============== 类型定义 ==============

interface MultipartResult {
  body: string;
  contentType: string;
}

interface LoginParams {
  username: string;
  password: string;
  captchaId: string;
  captcha: string;
  type: string;
}

export interface LoginResultData {
  success: boolean;
  uid: string;
  cid: string;
  error: string;
  setCookies: string[];
}

// ============== 常量 ==============

const NGA_RSA_PUBLIC_KEY =
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyKzZWDimCN1OCprqWUhF' +
  'UPhcwxDE62/BFVP6LtQHJu+65dm4YNmDvzitmcfaXW9YbhXnd4oP7j+6vpcgJQ+p' +
  '3ucySo1ZnqO0Bb2JKEtxpCmxe7IYXhFEkJqHpFYBTiAxQz2n2mX4JZy/ehBUSMjz' +
  'gzd0NdG6Ai1C42oCzYltUOjNWZUNHn1nqpElSWHnUWqkdN8+5ISP/ZMKiQdFANkE' +
  'qDGw3/34qyF+E/hVgrGF4/CcWNP/LJCdB6DYtx7VPlQZF0tP1s+q/++rC4rQ2wmV' +
  'l2V8zGh1j7ojZbt62hVjy6byK1E/2XYo97ZtL4KDW7F5jJMvSDRFR7901UR8hCdf' +
  '4wIDAQAB';

const DOMAINS: string[] = [
  'https://bbs.nga.cn',
  'https://ngabbs.com',
  'https://nga.178.com',
];

let activeDomainIndex: number = 0;

// ============== 工具函数 ==============

function stringToUint8Array(str: string): Uint8Array {
  const textEncoder = util.TextEncoder.create();
  return textEncoder.encodeInto(str);
}

function uint8ArrayToBase64(data: Uint8Array): string {
  const base64 = new util.Base64Helper();
  return base64.encodeToStringSync(data);
}

function decodeGb18030(buffer: ArrayBuffer): string {
  const decoder = util.TextDecoder.create('gb18030');
  return decoder.decodeToString(new Uint8Array(buffer));
}

function extractHostname(url: string): string {
  const match = url.match(/^https?:\/\/([^/]+)/);
  return match ? match[1] : url;
}

function buildUrl(baseUrl: string, path: string, params: Record<string, string>): string {
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
    const hasQuery = path.indexOf('?') >= 0
    url += (hasQuery ? '&' : '?') + qs.join('&');
  }
  return url;
}

function buildMultipart(fields: Record<string, string>): MultipartResult {
  const boundary = `----FormBoundary${Math.random().toString(36).slice(2)}`;
  const parts: string[] = [];
  const keys = Object.keys(fields);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="${key}"\r\n\r\n${fields[key]}\r\n`);
  }
  parts.push(`--${boundary}--\r\n`);
  const result: MultipartResult = {
    body: parts.join(''),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
  return result;
}

function emptyStringRecord(): Record<string, string> {
  const result: Record<string, string> = {};
  return result;
}

function buildEncodedBody(fields: Record<string, string>): string {
  const parts: string[] = [];
  const keys = Object.keys(fields);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(fields[key])}`);
  }
  return parts.join('&');
}

// ============== RSA 加密 ==============

async function encryptPassword(password: string): Promise<string> {
  // convertKey 需要 DER 编码的二进制数据，即 Base64 解码后的原始字节
  const base64 = new util.Base64Helper();
  const pubKeyData: cryptoFramework.DataBlob = {
    data: base64.decodeSync(NGA_RSA_PUBLIC_KEY),
  };

  const keyGenerator = cryptoFramework.createAsyKeyGenerator('RSA2048');
  const keyPair = await keyGenerator.convertKey(pubKeyData, null);
  const cipher = cryptoFramework.createCipher('RSA2048|PKCS1');
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
  const inputData: cryptoFramework.DataBlob = {
    data: stringToUint8Array(password),
  };
  const output = await cipher.doFinal(inputData);
  return uint8ArrayToBase64(output.data);
}

// ============== HTTP 请求 ==============

const LOG_CHUNK_SIZE: number = 1500;

function logChunks(prefix: string, text: string): void {
  if (text.length === 0) {
    return;
  }
  if (text.length <= LOG_CHUNK_SIZE) {
    console.info(prefix + text);
    return;
  }
  let offset = 0;
  let seq = 1;
  while (offset < text.length) {
    const end = Math.min(offset + LOG_CHUNK_SIZE, text.length);
    console.info(prefix + `[${seq}]` + text.slice(offset, end));
    offset = end;
    seq++;
  }
}

function httpReq(url: string, method: http.RequestMethod,
  header: Record<string, string>, body?: string): Promise<HttpResponse> {
  console.info('[NGA][REQ]', method, url);
  if (body && body.length > 0) {
    logChunks('[NGA][REQ] body:', body);
  }
  return new Promise<HttpResponse>((resolve, reject) => {
    const httpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method,
      header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 30000,
      connectTimeout: 15000,
    };
    if (body !== undefined) {
      options.extraData = body;
    }
    httpRequest.request(url, options, (err, response) => {
      httpRequest.destroy();
      if (err) {
        console.info('[NGA][REQ] fail:', url, err.message);
        reject(new Error(`HTTP请求失败: ${err.message}`));
        return;
      }
      console.info('[NGA][RES]', response.responseCode, url);
      resolve({ status: response.responseCode, body: response.result as ArrayBuffer });
    });
  });
}

interface HttpResponse {
  status: number
  body: ArrayBuffer
}

// ============== NGA 核心 ==============

async function ngaGet(path: string, params: Record<string, string>,
  cookies?: Cookies, extraHeaders?: Record<string, string>): Promise<object> {
  return ngaRequest(path, http.RequestMethod.GET, params, '', cookies, '', extraHeaders);
}

async function ngaPost(path: string, body: Record<string, string>,
  cookies?: Cookies): Promise<object> {
  return ngaRequest(path, http.RequestMethod.POST, emptyStringRecord(),
    buildEncodedBody(body), cookies, '', emptyStringRecord());
}

async function ngaPostWithQuery(path: string, params: Record<string, string>,
  cookies?: Cookies): Promise<object> {
  const extraHeaders: Record<string, string> = {
    'Content-Length': '0',
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36',
  };
  return ngaRequest(path, http.RequestMethod.POST, params,
    '', cookies, '', extraHeaders, true);
}

async function ngaPostMultipart(path: string, fields: Record<string, string>,
  cookies?: Cookies, baseUrl: string = ''): Promise<object> {
  const mp = buildMultipart(fields);
  const headers: Record<string, string> = emptyStringRecord();
  headers['Content-Type'] = mp.contentType;
  return ngaRequest(path, http.RequestMethod.POST, emptyStringRecord(),
    mp.body, cookies, baseUrl, headers);
}

async function ngaGetRaw(path: string, params: Record<string, string>,
  extraHeaders?: Record<string, string>): Promise<ArrayBuffer> {
  const result = await rawRequest(path, http.RequestMethod.GET, params, '', extraHeaders);
  return result;
}

async function ngaGetHtmlText(path: string, params: Record<string, string>,
  cookies?: Cookies): Promise<string> {
  const baseUrl: string = DOMAINS[activeDomainIndex];
  const hostname: string = extractHostname(baseUrl);
  let released: boolean = false;
  let response: HttpResponse = { status: 0, body: new ArrayBuffer(0) };
  let firstErrorMsg: string = '';

  try {
    await ngaThrottler.acquire(hostname);

    const url: string = buildUrl(baseUrl, path, params);
    const header: Record<string, string> = {
      'User-Agent': 'NGA_WP_JW',
      'X-User-Agent': 'Nga_Official',
    };
    if (cookies) {
      header['Cookie'] = `ngaPassportUid=${cookies.uid}; ngaPassportCid=${cookies.cid}`;
    }

    try {
      response = await httpReq(url, http.RequestMethod.GET, header);
    } catch (firstError) {
      firstErrorMsg = (firstError as Error).message;
      ngaThrottler.release(hostname);
      released = true;

      let retrySuccess = false;
      for (let i = 1; i < DOMAINS.length; i++) {
        const retryDomainIdx = (activeDomainIndex + i) % DOMAINS.length;
        const retryBaseUrl = baseUrl || DOMAINS[retryDomainIdx];
        const retryHostname = extractHostname(retryBaseUrl);

        await ngaThrottler.acquire(retryHostname);
        try {
          const retryUrl = buildUrl(retryBaseUrl, path, params);
          response = await httpReq(retryUrl, http.RequestMethod.GET, header);
          retrySuccess = true;
          break;
        } catch (retryError) {
          firstErrorMsg = (retryError as Error).message;
        } finally {
          ngaThrottler.release(retryHostname);
        }
      }

      if (!retrySuccess) {
        throw new Error(`请求失败: ${firstErrorMsg}`);
      }
    }

    return decodeGb18030(response.body);
  } finally {
    if (!released) {
      ngaThrottler.release(hostname);
    }
  }
}

async function ngaGetWithBaseUrl(path: string, params: Record<string, string>,
  baseUrl: string, cookies?: Cookies): Promise<object> {
  return ngaRequest(path, http.RequestMethod.GET, params, '', cookies, baseUrl, emptyStringRecord());
}

export interface Cookies {
  uid: string;
  cid: string;
}

/**
 * NGA API 核心请求
 */
async function ngaRequest(path: string, method: http.RequestMethod,
  params: Record<string, string>, body: string,
  cookies: Cookies | undefined, baseUrl: string,
  extraHeaders: Record<string, string> | undefined,
  skipInchst?: boolean): Promise<object> {
  const resolvedBaseUrl = baseUrl || DOMAINS[activeDomainIndex];
  const hostname = extractHostname(resolvedBaseUrl);

  if (!skipInchst && !params['__inchst']) {
    params['__inchst'] = 'UTF8';
  }

  let released = false;

  try {
    await ngaThrottler.acquire(hostname);

    const url = buildUrl(resolvedBaseUrl, path, params);
    const header: Record<string, string> = {
      'User-Agent': 'NGA_WP_JW',
      'X-User-Agent': 'Nga_Official',
    };

    if (extraHeaders) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        header[keys[i]] = extraHeaders[keys[i]];
      }
    }

    if (cookies) {
      header['Cookie'] = `ngaPassportUid=${cookies.uid}; ngaPassportCid=${cookies.cid}`;
    }

    if (method === http.RequestMethod.POST) {
      if (body && !header['Content-Type']) {
        header['Content-Type'] = 'application/x-www-form-urlencoded';
      }
      if (!header['Content-Length']) {
        header['Content-Length'] = body ? String(body.length) : '0';
      }
    }

    let response: HttpResponse = { status: 0, body: new ArrayBuffer(0) };
    let firstErrorMsg = '';
    try {
      response = await httpReq(url, method, header, body);
    } catch (firstError) {
      firstErrorMsg = (firstError as Error).message;
      ngaThrottler.release(hostname);
      released = true;

      let retrySuccess = false;
      for (let i = 1; i < DOMAINS.length; i++) {
        const retryDomainIdx = (activeDomainIndex + i) % DOMAINS.length;
        const retryBaseUrl = baseUrl || DOMAINS[retryDomainIdx];
        const retryHostname = extractHostname(retryBaseUrl);

        await ngaThrottler.acquire(retryHostname);
        try {
          const retryUrl = buildUrl(retryBaseUrl, path, params);
          response = await httpReq(retryUrl, method, header, body);
          retrySuccess = true;
          break;
        } catch (retryError) {
          firstErrorMsg = (retryError as Error).message;
        } finally {
          ngaThrottler.release(retryHostname);
        }
      }

      if (!retrySuccess) {
        throw new Error(`请求失败: ${firstErrorMsg}`);
      }
    }

    // GB18030 解码
    const rawText = decodeGb18030(response.body);
    logChunks('[NGA][RES] body:', rawText);

    // 处理 HTML 错误页
    const trimmed = rawText.trimStart();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html')) {
      const msgMatch = rawText.match(/<!--msginfostart-->([\s\S]*?)<!--msginfoend-->/);
      const codeMatch = rawText.match(/<!--msgcodestart-->(\d+)<!--msgcodeend-->/);
      const titleMatch = rawText.match(/<title>([\s\S]*?)<\/title>/);
      const htmlError = msgMatch ? msgMatch[1].replace(/<[^>]+>/g, '').trim()
        : titleMatch ? titleMatch[1].trim()
        : '服务器返回了非预期的HTML页面';

      const errObj: Record<string, string> = { '0': htmlError };
      const result: Record<string, Object> = { 'error': errObj as Object };
      if (codeMatch) {
        const codeNum = Number(codeMatch[1]);
        result['error_code'] = codeNum as Object;
      }
      return result;
    }

    // JSON 处理
    const text = preprocessJson(rawText);
    try {
      return JSON.parse(text) as Record<string, Object>;
    } catch (parseError) {
      const errResult: Record<string, Object> = {
        '__parseError': true as Object,
        '__rawLength': text.length as Object,
        'error': new Error((parseError as Error).message) as Object,
      };
      return errResult;
    }
  } finally {
    if (!released) {
      ngaThrottler.release(hostname);
    }
  }
}

async function rawRequest(path: string, method: http.RequestMethod,
  params: Record<string, string>, body: string,
  extraHeaders: Record<string, string> | undefined): Promise<ArrayBuffer> {
  const baseUrl = DOMAINS[activeDomainIndex];
  const url = buildUrl(baseUrl, path, params);
  const header: Record<string, string> = {
    'User-Agent': 'NGA_WP_JW',
    'X-User-Agent': 'Nga_Official',
  };
  if (extraHeaders) {
    const keys = Object.keys(extraHeaders);
    for (let i = 0; i < keys.length; i++) {
      header[keys[i]] = extraHeaders[keys[i]];
    }
  }
  const httpResult = await httpReq(url, method, header, body);
  return httpResult.body;
}

// ============== 公共接口 ==============

interface INgaClient {
  get: (path: string, params: Record<string, string>,
    cookies?: Cookies, extraHeaders?: Record<string, string>) => Promise<object>;
  post: (path: string, body: Record<string, string>, cookies?: Cookies) => Promise<object>;
  postWithQuery: (path: string, params: Record<string, string>, cookies?: Cookies) => Promise<object>;
  postMultipart: (path: string, fields: Record<string, string>,
    cookies?: Cookies, baseUrl?: string) => Promise<object>;
  getRaw: (path: string, params: Record<string, string>,
    extraHeaders?: Record<string, string>) => Promise<ArrayBuffer>;
  getWithBaseUrl: (path: string, params: Record<string, string>,
    baseUrl: string, cookies?: Cookies) => Promise<object>;
  getHtmlText: (path: string, params: Record<string, string>,
    cookies?: Cookies) => Promise<string>;
  getCaptchaV2: (captchaId: string) => Promise<string>;
  loginPassword: (loginParams: LoginParams) => Promise<LoginResultData>;
  rotateDomain: () => void;
  getActiveDomain: () => string;
  setActiveDomainIndex: (index: number) => void;
  getDomainList: () => string[];
}

const client: INgaClient = {
  async get(path: string, params: Record<string, string>,
    cookies?: Cookies, extraHeaders?: Record<string, string>): Promise<object> {
    return ngaGet(path, params, cookies, extraHeaders);
  },

  async post(path: string, body: Record<string, string>,
    cookies?: Cookies): Promise<object> {
    return ngaPost(path, body, cookies);
  },

  async postWithQuery(path: string, params: Record<string, string>,
    cookies?: Cookies): Promise<object> {
    return ngaPostWithQuery(path, params, cookies);
  },

  async postMultipart(path: string, fields: Record<string, string>,
    cookies?: Cookies, baseUrl?: string): Promise<object> {
    return ngaPostMultipart(path, fields, cookies, baseUrl || '');
  },

  async getRaw(path: string, params: Record<string, string>,
    extraHeaders?: Record<string, string>): Promise<ArrayBuffer> {
    return ngaGetRaw(path, params, extraHeaders);
  },

  async getWithBaseUrl(path: string, params: Record<string, string>,
    baseUrl: string, cookies?: Cookies): Promise<object> {
    return ngaGetWithBaseUrl(path, params, baseUrl, cookies);
  },

  async getHtmlText(path: string, params: Record<string, string>,
    cookies?: Cookies): Promise<string> {
    return ngaGetHtmlText(path, params, cookies);
  },

  async getCaptchaV2(captchaId: string): Promise<string> {
    const params: Record<string, string> = { 'id': captchaId, 'from': 'login' };
    const headers: Record<string, string> = {
      'Referer': 'https://bbs.nga.cn/nuke/account_copy.html?login',
    };
    const buffer = await ngaGetRaw('/login_check_code.php', params, headers);
    const base64 = uint8ArrayToBase64(new Uint8Array(buffer));
    return `data:image/png;base64,${base64}`;
  },

  async loginPassword(loginParams: LoginParams): Promise<LoginResultData> {
    const encryptedPassword = await encryptPassword(loginParams.password);

    const fields: Record<string, string> = {
      '__lib': 'login',
      '__output': '1',
      '__act': 'login',
      '__inchst': 'UTF-8',
      'app_id': '5004',
      'device': '',
      'name': loginParams.username,
      'type': loginParams.type,
      'password': encryptedPassword,
      'rid': loginParams.captchaId,
      'captcha': loginParams.captcha.toUpperCase(),
    };

    const mp = buildMultipart(fields);
    const header: Record<string, string> = {
      'User-Agent': 'NGA_WP_JW',
      'X-User-Agent': 'Nga_Official',
      'Referer': 'https://bbs.nga.cn/nuke/account_copy.html?login',
      'Origin': 'https://bbs.nga.cn',
      'Content-Type': mp.contentType,
      'Accept': '*/*',
    };

    const httpRequest = http.createHttp();
    const response = await new Promise<http.HttpResponse>((resolve, reject) => {
      httpRequest.request('https://bbs.nga.cn/nuke.php', {
        method: http.RequestMethod.POST,
        header,
        extraData: mp.body,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 30000,
        connectTimeout: 15000,
      }, (err, resp) => {
        if (err) {
          reject(new Error(`登录请求失败: ${err.message}`));
          return;
        }
        resolve(resp);
      });
    });
    httpRequest.destroy();

    const bodyText = decodeGb18030(response.result as ArrayBuffer);
    const setCookieHeader = response.header['set-cookie'] as string | string[] | undefined;
    const cookies: string[] = [];
    if (Array.isArray(setCookieHeader)) {
      for (let i = 0; i < (setCookieHeader as string[]).length; i++) {
        cookies.push((setCookieHeader as string[])[i]);
      }
    } else if (typeof setCookieHeader === 'string') {
      cookies.push(setCookieHeader as string);
    }

    let uid = '';
    let cid = '';
    for (let i = 0; i < cookies.length; i++) {
      const c = cookies[i];
      const uidMatch = c.match(/ngaPassportUid=(\d+)/);
      const cidMatch = c.match(/ngaPassportCid=([^;]+)/);
      if (uidMatch) uid = uidMatch[1];
      if (cidMatch) cid = cidMatch[1];
    }

    if (!uid || !cid) {
      const cleaned = preprocessJson(bodyText);
      let parsed: Record<string, Object> | null = null;
      try { parsed = JSON.parse(cleaned) as Record<string, Object>; } catch (e) { /* */ }      const parsedData = parsed?.['data'] as Record<string, Object> | undefined;
      if (parsedData && parsedData['1'] && parsedData['2']) {
        uid = String(parsedData['1']);
        cid = String(parsedData['2']);
      }
    }

    if (uid && cid) {
      const result: LoginResultData = {
        success: true, uid, cid, error: '', setCookies: cookies,
      };
      return result;
    }

    const cleaned = preprocessJson(bodyText);
    let parsed: Record<string, Object> | null = null;
    try { parsed = JSON.parse(cleaned); } catch (e) { /* */ }
    const errorObj = parsed?.['error'] as Record<string, string> | undefined;
    const errorMsg = errorObj?.['0'] ?? bodyText.slice(0, 300);

    const failResult: LoginResultData = {
      success: false, uid: '', cid: '', error: errorMsg, setCookies: cookies,
    };
    return failResult;
  },

  rotateDomain(): void {
    activeDomainIndex = (activeDomainIndex + 1) % DOMAINS.length;
  },

  getActiveDomain(): string {
    return DOMAINS[activeDomainIndex];
  },

  setActiveDomainIndex(index: number): void {
    if (index >= 0 && index < DOMAINS.length) {
      activeDomainIndex = index;
    }
  },

  getDomainList(): string[] {
    return DOMAINS.slice();
  },
};

export const ngaClient: INgaClient = client;

/**
 * 上传附件到 img8.nga.cn （Multipart + 二进制）
 * 对应 Java TopicPostModel.buildMultipartBody() + uploadFileInner()
 */
export async function ngaUploadFile(
  imageData: ArrayBuffer,
  fileName: string,
  auth: string,
  fid: number,
  cookies: Cookies
): Promise<string> {
  const url: string = 'https://img8.nga.cn/attach.php'
  const boundary: string = '----NGAFormBoundary' + Math.random().toString(36).slice(2, 12)
  const encoder: util.TextEncoder = util.TextEncoder.create()

  const textFields: string =
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="attachment_file1_url_utf8_name"\r\n\r\n' + fileName + '\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="fid"\r\n\r\n' + String(fid) + '\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="auth"\r\n\r\n' + auth + '\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="func"\r\n\r\nupload\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="v2"\r\n\r\n1\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="lite"\r\n\r\njs\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="attachment_file1_auto_size"\r\n\r\n\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="attachment_file1_watermark"\r\n\r\n\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="attachment_file1_dscp"\r\n\r\n\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="attachment_file1_img"\r\n\r\n1\r\n' +
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="origin_domain"\r\n\r\nbbs.ngacn.cc\r\n'

  const fileHeader: string =
    '--' + boundary + '\r\n' +
    'Content-Disposition: form-data; name="attachment_file1"; filename="' + fileName + '"\r\n' +
    'Content-Type: image/jpeg\r\n\r\n'
  const fileFooter: string = '\r\n--' + boundary + '--\r\n'

  const textBytes: Uint8Array = encoder.encodeInto(textFields)
  const headerBytes: Uint8Array = encoder.encodeInto(fileHeader)
  const footerBytes: Uint8Array = encoder.encodeInto(fileFooter)
  const imageU8: Uint8Array = new Uint8Array(imageData)

  const totalLength: number = textBytes.byteLength + headerBytes.byteLength + imageU8.byteLength + footerBytes.byteLength
  const fullBody: Uint8Array = new Uint8Array(totalLength)
  let pos: number = 0
  fullBody.set(textBytes, pos)
  pos += textBytes.byteLength
  fullBody.set(headerBytes, pos)
  pos += headerBytes.byteLength
  fullBody.set(imageU8, pos)
  pos += imageU8.byteLength
  fullBody.set(footerBytes, pos)

  const contentType: string = 'multipart/form-data; boundary=' + boundary
  const headers: Record<string, string> = {
    'Content-Type': contentType,
    'User-Agent': 'NGA_WP_JW',
    'X-User-Agent': 'Nga_Official',
  }
  if (cookies) {
    headers['Cookie'] = 'ngaPassportUid=' + cookies.uid + '; ngaPassportCid=' + cookies.cid
  }

  console.info('[NGA][UPLOAD]', url, 'size:', String(imageData.byteLength))
  return new Promise<string>((resolve, reject) => {
    const httpRequest = http.createHttp()
    httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: fullBody.buffer as ArrayBuffer,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 120000,
      connectTimeout: 30000,
    }, (err, resp) => {
      httpRequest.destroy()
      if (err) {
        console.info('[NGA][UPLOAD] fail:', err.message)
        reject(new Error('上传失败: ' + err.message))
        return
      }
      const respText: string = decodeGb18030(resp.result as ArrayBuffer)
      console.info('[NGA][UPLOAD] resp', String(resp.responseCode), respText.slice(0, 200))
      if (resp.responseCode !== 200) {
        reject(new Error('上传HTTP ' + String(resp.responseCode)))
        return
      }
      resolve(respText)
    })
  })
}

