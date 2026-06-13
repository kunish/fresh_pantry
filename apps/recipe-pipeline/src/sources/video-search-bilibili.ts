import type { DishQuery, Log } from '../clean/fetch-images';
import type { VideoCandidate, VideoSearchProvider } from '../clean/fetch-videos';

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36';

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, '');
}

/** "13:43" / "5:6" → 秒;非法返回 undefined。 */
function parseDuration(d: unknown): number | undefined {
  if (typeof d !== 'string') return undefined;
  const parts = d.split(':').map(Number);
  if (!parts.length || parts.some((n) => Number.isNaN(n))) return undefined;
  return parts.reduce((acc, n) => acc * 60 + n, 0);
}

export interface BilibiliSearchOptions {
  fetchImpl?: typeof fetch;
  log?: Log;
}

interface BiliResultItem {
  bvid?: string;
  title?: string;
  author?: string;
  play?: number;
  duration?: string;
}

/**
 * B站公开搜索 provider(免 key,确定性可复跑)。先访问 bilibili.com 拿 buvid cookie,
 * 再调 search/type 接口(实测无需 WBI 签名)。搜「<菜名> 做法」,候选按 B站相关度降序。
 * cookie 跨多次搜索复用。
 */
export function createBilibiliVideoSearch(opts: BilibiliSearchOptions = {}): VideoSearchProvider {
  const fetchImpl = opts.fetchImpl ?? fetch;
  let cookie: string | null = null;

  async function ensureCookie(): Promise<string> {
    if (cookie !== null) return cookie;
    const res = await fetchImpl('https://www.bilibili.com/', { headers: { 'User-Agent': UA } });
    const h = res.headers as Headers & { getSetCookie?: () => string[] };
    const raws = h.getSetCookie?.() ?? (h.get('set-cookie') ? [h.get('set-cookie') as string] : []);
    // 取每条 set-cookie 的 name=value 片段拼成 Cookie 头(buvid3/buvid4/b_nut 等)
    cookie = raws.map((c) => c.split(';')[0].trim()).filter(Boolean).join('; ');
    return cookie;
  }

  return {
    async search(dish: DishQuery, log: Log): Promise<VideoCandidate[]> {
      try {
        const ck = await ensureCookie();
        const kw = encodeURIComponent(`${dish.name} 做法`);
        const url = `https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=${kw}&page=1`;
        const res = await fetchImpl(url, {
          headers: { 'User-Agent': UA, Referer: 'https://www.bilibili.com/', Cookie: ck },
        });
        const body = (await res.json()) as { code?: number; data?: { result?: BiliResultItem[] } };
        if (body.code !== 0 || !Array.isArray(body.data?.result)) {
          log(`B站搜索无结果: ${dish.name}(code ${body.code})`);
          return [];
        }
        return body.data.result
          .filter((v) => typeof v.bvid === 'string' && /^BV\w+$/.test(v.bvid))
          .map((v) => ({
            videoUrl: `https://www.bilibili.com/video/${v.bvid}`,
            sourcePage: `https://www.bilibili.com/video/${v.bvid}`,
            title: stripHtml(v.title ?? ''),
            provider: 'bilibili',
            author: v.author,
            play: typeof v.play === 'number' ? v.play : undefined,
            durationSec: parseDuration(v.duration),
          }));
      } catch (e) {
        log(`B站搜索失败: ${dish.name} ${e instanceof Error ? e.message : String(e)}`);
        return [];
      }
    },
  };
}
