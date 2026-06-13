import type { ImageSearchProvider, ImageCandidate, DishQuery, Log } from '../clean/fetch-images';

/**
 * 管线自带的默认搜图 provider:Openverse(openverse.org)聚合 CC 自由版权图,
 * 公开 JSON API、免 key,适合作为增量新菜的零配置自动补图。
 * 覆盖面有限(中式家常菜未必都有),所以全网最佳匹配 + 视觉校验仍由 ultracode
 * workflow 的 agent 充当 provider;两者输出同一 `ImageCandidate` 结构。
 */

const ENDPOINT = 'https://api.openverse.org/v1/images/';

interface OpenverseResult {
  url?: string;
  foreign_landing_url?: string;
  title?: string;
  license?: string;
  license_version?: string;
}

export interface OpenverseDeps {
  /** 注入以便测试;缺省走全局 fetch。返回解析后的 JSON,失败返回 null。 */
  fetchJson?: (url: string) => Promise<unknown>;
  pageSize?: number;
}

async function defaultFetchJson(url: string): Promise<unknown> {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'fresh-pantry-recipe-pipeline (+https://github.com/kunish)' },
  }).catch(() => null);
  if (!res || !res.ok) return null;
  return res.json().catch(() => null);
}

export function createOpenverseSearch(deps: OpenverseDeps = {}): ImageSearchProvider {
  const fetchJson = deps.fetchJson ?? defaultFetchJson;
  const pageSize = deps.pageSize ?? 8;
  return {
    async search(dish: DishQuery, log: Log): Promise<ImageCandidate[]> {
      const params = new URLSearchParams({
        q: dish.name,
        mature: 'false',
        category: 'photograph',
        page_size: String(pageSize),
      });
      const data = (await fetchJson(`${ENDPOINT}?${params}`).catch(() => null)) as
        | { results?: OpenverseResult[] }
        | null;
      const results = data?.results ?? [];
      const candidates = results
        .filter((r): r is OpenverseResult & { url: string } => typeof r.url === 'string' && r.url.length > 0)
        .map((r) => ({
          url: r.url,
          sourcePage: r.foreign_landing_url,
          title: r.title,
          license: r.license
            ? `${r.license}${r.license_version ? ' ' + r.license_version : ''}`.toUpperCase()
            : undefined,
        }));
      if (!candidates.length) log(`Openverse 无结果: ${dish.name}`);
      return candidates;
    },
  };
}
