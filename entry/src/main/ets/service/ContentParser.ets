/**
 * NGA BBCode → HTML 内容解析器
 * 使用 string.replace 的回调在 ArkTS 中需要显式参数类型
 */

const NGA_CDN_HOSTS: string[] = ['img.nga.178.com', 'img2.nga.178.com', 'img4.nga.178.com', 'img8.nga.cn'];

function stripThumbnailSuffix(url: string): string {
  let result: string = url
    .replace(/\.thumb_s(\.\w+)$/i, '$1')
    .replace(/\.thumb_m(\.\w+)$/i, '$1')
    .replace(/\.medium(\.\w+)$/i, '$1')
    .replace(/\.thumb(\.\w+)$/i, '$1');
  const dot: number = result.lastIndexOf('.')
  if (dot > 0) {
    const ext: string = result.substring(dot)
    const prev: string = result.substring(0, dot)
    if (prev.endsWith(ext)) {
      result = prev
    }
  }
  return result
}

export function resolveAttachUrl(attachurl: string): string {
  if (!attachurl) return '';
  if (attachurl.startsWith('http')) return attachurl;
  if (/^[\d]+$/.test(attachurl) || !attachurl.includes('/')) return '';
  return `https://img.nga.178.com/attachments/${attachurl}`;
}

export function parseNgaContent(content: string): string {
  if (!content || typeof content !== 'string') return '';

  let html = content;

  // [pid=X,Y,Z]text[/pid]
  html = html.replace(/\[pid=(\d+),(\d+),(\d+)\](.*?)\[\/pid\]/g,
    (substring: string, p1: string, p2: string, p3: string, p4: string): string =>
      `<a href="#/thread?tid=${p2}&pid=${p1}">${p4}</a>`
  );

  // [uid=X]text[/uid]
  html = html.replace(/\[uid=(\d+)\](.*?)\[\/uid\]/g,
    (s: string, p1: string, p2: string): string => `<a href="#/profile?uid=${p1}">${p2}</a>`
  );

  // [tid=X]text[/tid]
  html = html.replace(/\[tid=(\d+)(?:&page=(\d+))?\](.*?)\[\/tid\]/g,
    (s: string, p1: string, p2: string, p3: string): string =>
      `<a href="#/thread?tid=${p1}${p2 ? '&page=' + p2 : ''}">${p3}</a>`
  );

  // [@X]
  html = html.replace(/\[@(\d+)\]/g,
    (s: string, p1: string): string => `<a href="#/profile?uid=${p1}">@${p1}</a>`
  );

  // Post by ...
  html = html.replace(/Post by (.+?) \((\d+)\)/g,
    (s: string, p1: string, p2: string): string =>
      `Post by <a href="#/profile?uid=${p2}">${p1}</a> (${p2})`
  );

  // 表情 [s:cat:code]
  html = html.replace(/\[s:(\w+):([^\]]+)\]/g,
    (s: string, p1: string, p2: string): string => `[表情:${p1}:${p2}]`
  );

  // [s:N] 旧表情
  html = html.replace(/\[s:(\d+)\]/g,
    (s: string, p1: string): string => `[表情${p1}]`
  );

  // [img]./mon_xxx[/img] NGA 内部图片
  html = html.replace(/\[img\]\.(\/mon_\S+?)\[\/img\]/g,
    (s: string, p1: string): string => {
      const cleanPath = stripThumbnailSuffix(p1);
      return `<img src="https://img.nga.178.com/attachments${cleanPath}" style="max-width:100%;height:auto;border-radius:8px;">`;
    }
  );

  // [collapse=title]body[/collapse]
  html = html.replace(/\[collapse=(.*?)\](.*?)\[\/collapse\]/gs,
    (s: string, p1: string, p2: string): string => `<details><summary>${p1}</summary>${p2}</details>`
  );

  // [quote]body[/quote] 最多3层
  for (let i = 0; i < 3; i++) {
    html = html.replace(/\[quote\](.*?)\[\/quote\]/gs,
      (s: string, p1: string): string => `<blockquote>${p1}</blockquote>`
    );
  }

  // [dice]data[/dice]
  html = html.replace(/\[dice\](.*?)\[\/dice\]/g,
    (s: string, p1: string): string => `🎲 骰子`
  );

  // [flash=video]url[/flash]
  html = html.replace(/\[flash=video\](.*?)\[\/flash\]/g,
    (s: string, p1: string): string => `<video src="${p1}" controls></video>`
  );

  // [flash=audio]url[/flash]
  html = html.replace(/\[flash=audio\](.*?)\[\/flash\]/g,
    (s: string, p1: string): string => `<audio src="${p1}" controls></audio>`
  );

  // [flash]url[/flash] — 根据扩展名推断类型
  html = html.replace(/\[flash\](.*?)\[\/flash\]/g,
    (s: string, p1: string): string => {
      const url: string = p1.trim()
      const extMatch: RegExpExecArray | null = /\.(\w+)(\?.*)?$/.exec(url)
      const ext: string = extMatch ? extMatch[1].toLowerCase() : ''
      const videoExts: string[] = ['mp4', 'webm', 'ogg', 'mov', '3gp']
      const audioExts: string[] = ['mp3', 'wav', 'flac', 'aac', 'm4a']
      if (videoExts.indexOf(ext) >= 0) {
        return `<video src="${url}" controls></video>`
      } else if (audioExts.indexOf(ext) >= 0) {
        return `<audio src="${url}" controls></audio>`
      }
      return `[Flash]`
    }
  );

  // [lessernuke]body[/lessernuke]
  html = html.replace(/\[lessernuke\](.*?)\[\/lessernuke\]/gs,
    (s: string, p1: string): string => p1
  );

  // [album=title]body[/album]
  html = html.replace(/\[album=(.*?)\](.*?)\[\/album\]/gs,
    (s: string, p1: string, p2: string): string => p2
  );

  // 移除 [hip] [comment] [randomblock]
  html = html.replace(/\[hip\](.*?)\[\/hip\]/gs, (s: string, p1: string): string => p1);
  html = html.replace(/\[comment[^\]]*\]/g, '');
  html = html.replace(/\[randomblock\]/g, '');

  // [code]code[/code]
  html = html.replace(/\[code\](.*?)\[\/code\]/gs,
    (s: string, p1: string): string => `<pre><code>${p1}</code></pre>`
  );

  // 格式化标签
  html = html.replace(/\[b\](.*?)\[\/b\]/g, (s: string, p1: string): string => `<strong>${p1}</strong>`);
  html = html.replace(/\[i\](.*?)\[\/i\]/g, (s: string, p1: string): string => `<em>${p1}</em>`);
  html = html.replace(/\[u\](.*?)\[\/u\]/g, (s: string, p1: string): string => `<u>${p1}</u>`);
  html = html.replace(/\[del\](.*?)\[\/del\]/g, (s: string, p1: string): string => `<del>${p1}</del>`);
  html = html.replace(/\[h\](.*?)\[\/h\]/g, (s: string, p1: string): string => `<strong>${p1}</strong>`);
  html = html.replace(/\[item\](.*?)\[\/item\]/g, (s: string, p1: string): string => `<strong>${p1}</strong>`);

  html = html.replace(/\[l\](.*?)\[\/l\]/gs, (s: string, p1: string): string => p1);
  html = html.replace(/\[r\](.*?)\[\/r\]/gs, (s: string, p1: string): string => p1);

  html = html.replace(/\[color=(#[0-9a-fA-F]+|\w+)\](.*?)\[\/color\]/gs,
    (s: string, p1: string, p2: string): string => `<span>${p2}</span>`);
  html = html.replace(/\[size=(\d+)\](.*?)\[\/size\]/gs,
    (s: string, p1: string, p2: string): string => `<span>${p2}</span>`);
  html = html.replace(/\[font=(.*?)\](.*?)\[\/font\]/gs,
    (s: string, p1: string, p2: string): string => `<span>${p2}</span>`);

  html = html.replace(/\[url=(.*?)\](.*?)\[\/url\]/g,
    (s: string, p1: string, p2: string): string => `<a href="${p1}">${p2}</a>`);
  html = html.replace(/\[url\](.*?)\[\/url\]/g,
    (s: string, p1: string): string => `<a href="${p1}">${p1}</a>`);

  // [img]url[/img] 通用图片
  html = html.replace(/\[img\](.*?)\[\/img\]/g,
    (s: string, p1: string): string => {
      const cleanUrl = stripThumbnailSuffix(p1);
      return `<img src="${cleanUrl}" style="max-width:100%;height:auto;border-radius:8px;">`;
    }
  );

  // [list][*]item[/list]
  html = html.replace(/\[list\](.*?)\[\/list\]/gs, (s: string, p1: string): string => `<ul>${p1}</ul>`);
  html = html.replace(/\[\*\](.*?)(?=\[\*\]|\[\/list\])/gs, (s: string, p1: string): string => `<li>${p1}</li>`);

  // [align=x]content[/align]
  html = html.replace(/\[align=(\w+)\](.*?)\[\/align\]/gs,
    (s: string, p1: string, p2: string): string => `<div>${p2}</div>`);

  // [table] [tr] [td] [td=x,y,z]
  html = html.replace(/\[table\]/g, '<table>');
  html = html.replace(/\[\/table\]/g, '</table>');
  html = html.replace(/\[tr\]/g, '<tr>');
  html = html.replace(/\[\/tr\]/g, '</tr>');
  html = html.replace(/\[td(?:=(\d+))?(?:,(\d+))?(?:,(\d+))?\]/g, '<td>');
  html = html.replace(/\[\/td\]/g, '</td>');

  // [style x]content[/style]
  html = html.replace(/\[style\s+([^\]]*)\]/g, '<div>');
  html = html.replace(/\[\/style\]/g, '</div>');

  // 安全：移除 script 标签和事件处理
  html = html.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
  html = html.replace(/\bon\w+\s*=\s*["'][^"']*["']/gi, '');
  html = html.replace(/href\s*=\s*["']javascript:/gi, 'href="');

  return html;
}

export function extractContentImages(content: string): string[] {
  if (!content) return [];
  const urls: string[] = [];
  const pattern = /\[img\](.*?)\[\/img\]/g;
  let match = pattern.exec(content);
  while (match !== null) {
    const rawUrl = match[1];
    if (rawUrl.startsWith('.')) {
      const cleanPath = stripThumbnailSuffix(rawUrl.substring(1));
      urls.push(`https://img.nga.178.com/attachments${cleanPath}`);
    } else {
      urls.push(stripThumbnailSuffix(rawUrl));
    }
    match = pattern.exec(content);
  }
  return urls;
}

export function stripBbCode(content: string): string {
  if (!content) return '';
  let text = content;
  text = text.replace(/\[img\][^\[]*?\[\/img\]/gi, '');
  text = text.replace(/\[s:\w+:[^\]]+\]/g, '');
  text = text.replace(/\[s:\d+\]/g, '');
  text = text.replace(/\[\/?(?:pid|uid|tid|quote|collapse|code|b|i|u|del|h|item|l|r|color|size|font|url|list|align|table|tr|td|style|flash|lessernuke|album|hip|comment|randomblock|dice)[^\]]*\]/gi, '');
  text = text.replace(/\[@\d+\]/g, '');
  text = text.replace(/<[^>]+>/g, '');
  text = text.replace(/&#(\d+);/g, (_s: string, c: string): string => {
      const code: number = parseInt(c, 10)
      if (code <= 0xFFFF) return String.fromCharCode(code)
      const hi: number = 0xD800 + ((code - 0x10000) >> 10)
      const lo: number = 0xDC00 + ((code - 0x10000) & 0x3FF)
      return String.fromCharCode(hi) + String.fromCharCode(lo)
    });
  text = text.replace(/&\w+;/g, ' ');
  text = text.replace(/\s+/g, ' ').trim();
  return text;
}
