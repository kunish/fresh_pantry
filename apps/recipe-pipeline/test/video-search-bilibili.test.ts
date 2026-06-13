import { describe, it, expect, vi } from 'vitest';
import { createBilibiliVideoSearch } from '../src/sources/video-search-bilibili';

function mockHeaders(setCookies: string[]) {
  return {
    getSetCookie: () => setCookies,
    get: (k: string) => (k.toLowerCase() === 'set-cookie' ? setCookies.join(', ') : null),
  };
}

describe('createBilibiliVideoSearch', () => {
  it('先取 cookie 再搜,解析候选(去 HTML、构造 bvid URL、解析时长)', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce({ headers: mockHeaders(['buvid3=abc; Path=/', 'b_nut=1; Path=/']) })
      .mockResolvedValueOnce({ json: async () => ({ code: 0, data: { result: [
        { bvid: 'BV1aa', title: '红烧肉<em class="keyword">做法</em>', author: 'UP', play: 50000, duration: '13:43' },
      ] } }) });
    const search = createBilibiliVideoSearch({ fetchImpl: fetchImpl as unknown as typeof fetch });
    const out = await search.search({ id: 'r1', name: '红烧肉', category: '荤菜' }, () => {});
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(out[0]).toMatchObject({
      videoUrl: 'https://www.bilibili.com/video/BV1aa',
      title: '红烧肉做法', provider: 'bilibili', play: 50000, durationSec: 13 * 60 + 43,
    });
  });
  it('code 非 0 → 空数组(不抛)', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce({ headers: mockHeaders(['buvid3=abc']) })
      .mockResolvedValueOnce({ json: async () => ({ code: -412, data: null }) });
    const search = createBilibiliVideoSearch({ fetchImpl: fetchImpl as unknown as typeof fetch });
    expect(await search.search({ id: 'r1', name: 'x', category: '荤菜' }, () => {})).toEqual([]);
  });
  it('cookie 只取一次(跨多次搜索复用)', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce({ headers: mockHeaders(['buvid3=abc']) })
      .mockResolvedValue({ json: async () => ({ code: 0, data: { result: [] } }) });
    const search = createBilibiliVideoSearch({ fetchImpl: fetchImpl as unknown as typeof fetch });
    await search.search({ id: 'a', name: 'a', category: '荤菜' }, () => {});
    await search.search({ id: 'b', name: 'b', category: '荤菜' }, () => {});
    expect(fetchImpl).toHaveBeenCalledTimes(3); // 1 引导 + 2 搜索
  });
});
