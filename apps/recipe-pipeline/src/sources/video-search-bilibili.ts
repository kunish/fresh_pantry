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
  /** 命中风控后的退避等待时间(ms),默认 3000。 */
  riskBackoffMs?: number;
  /** 可注入的 sleep 函数(测试用),默认 setTimeout。 */
  sleep?: (ms: number) => Promise<void>;
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
  const riskBackoffMs = opts.riskBackoffMs ?? 3000;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
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

  /** 执行一次 API 搜索;返回候选数组,或 'risk'(命中风控/JSON 解析失败/code 非 0)。 */
  async function querySearch(dish: DishQuery, ck: string): Promise<VideoCandidate[] | 'risk'> {
    const kw = encodeURIComponent(`${dish.name} 做法`);
    const url = `https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=${kw}&page=1`;
    const res = await fetchImpl(url, {
      headers: { 'User-Agent': UA, Referer: 'https://www.bilibili.com/', Cookie: ck },
    });
    let body: { code?: number; data?: { result?: BiliResultItem[] } };
    try {
      body = (await res.json()) as { code?: number; data?: { result?: BiliResultItem[] } };
    } catch {
      // res.json() 抛说明返回了 HTML 风控页,非 JSON
      return 'risk';
    }
    if (body.code !== 0) return 'risk';
    if (!Array.isArray(body.data?.result)) return [];
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
  }

  return {
    async search(dish: DishQuery, log: Log): Promise<VideoCandidate[]> {
      try {
        let ck = await ensureCookie();
        let r = await querySearch(dish, ck);
        if (r === 'risk') {
          log(`B站风控,重取 cookie + 退避重试: ${dish.name}`);
          cookie = null; // 强制下次重新引导 cookie
          await sleep(riskBackoffMs);
          ck = await ensureCookie();
          r = await querySearch(dish, ck);
          if (r === 'risk') { log(`B站仍风控,跳过: ${dish.name}`); return []; }
        }
        return r;
      } catch (e) {
        log(`B站搜索失败: ${dish.name} ${e instanceof Error ? e.message : String(e)}`);
        return [];
      }
    },
  };
}
