import { describe, it, expect } from 'vitest';
import { createOpenverseSearch } from '../src/sources/image-search-openverse';
import type { DishQuery } from '../src/clean/fetch-images';

const dish: DishQuery = { id: 'howtocook:aquatic/咖喱炒蟹', name: '咖喱炒蟹', category: '水产' };
const noop = () => {};

describe('createOpenverseSearch', () => {
  it('把 Openverse results 映射成候选(url/来源页/标题/许可)', async () => {
    let calledUrl = '';
    const search = createOpenverseSearch({
      fetchJson: async (url) => {
        calledUrl = url;
        return {
          results: [
            {
              url: 'https://cdn.test/crab.jpg',
              foreign_landing_url: 'https://flickr.test/p/1',
              title: 'Curry Crab',
              license: 'by',
              license_version: '2.0',
            },
            { url: 'https://cdn.test/crab2.jpg', license: 'cc0' },
          ],
        };
      },
    });
    const cands = await search.search(dish, noop);
    expect(calledUrl).toContain('q=%E5%92%96%E5%96%B1%E7%82%92%E8%9F%B9');
    expect(calledUrl).toContain('category=photograph');
    expect(cands).toHaveLength(2);
    expect(cands[0]).toEqual({
      url: 'https://cdn.test/crab.jpg',
      sourcePage: 'https://flickr.test/p/1',
      title: 'Curry Crab',
      license: 'BY 2.0',
    });
    expect(cands[1].license).toBe('CC0');
  });

  it('丢弃没有 url 的结果', async () => {
    const search = createOpenverseSearch({
      fetchJson: async () => ({ results: [{ title: '无图' }, { url: 'https://cdn.test/ok.jpg' }] }),
    });
    const cands = await search.search(dish, noop);
    expect(cands).toHaveLength(1);
    expect(cands[0].url).toBe('https://cdn.test/ok.jpg');
  });

  it('请求失败 / 空结果 → 返回空数组,不抛', async () => {
    const fail = createOpenverseSearch({ fetchJson: async () => null });
    expect(await fail.search(dish, noop)).toEqual([]);
    const empty = createOpenverseSearch({ fetchJson: async () => ({ results: [] }) });
    expect(await empty.search(dish, noop)).toEqual([]);
  });
});
