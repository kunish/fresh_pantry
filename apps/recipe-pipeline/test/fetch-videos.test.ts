import { describe, it, expect } from 'vitest';
import { acquireMissingVideos, mergeVideoAttributions, type VideoAttribution, type VideoSearchProvider, type VideoCandidate } from '../src/clean/fetch-videos';
import type { CleanRecipe } from '../src/clean/schema';

const r = (over: Partial<CleanRecipe> = {}): CleanRecipe => ({
  id: 'r1', name: '番茄炒蛋', category: '荤菜', difficulty: 1, cookingMinutes: 10,
  description: 'd', ingredients: [], steps: [], tags: [], imageUrl: null,
  videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
});

describe('acquireMissingVideos', () => {
  const stub = (byName: Record<string, VideoCandidate[]>): VideoSearchProvider => ({
    async search(dish) { return byName[dish.name] ?? []; },
  });
  it('给缺视频的菜选首个达播放阈值的候选 + 出处;无候选留 null', async () => {
    const recipes = [r({ id: 'a', name: '红烧肉' }), r({ id: 'b', name: '无果菜' })];
    const search = stub({ '红烧肉': [
      { videoUrl: 'https://www.bilibili.com/video/BV1lo', title: '低播放', provider: 'bilibili', play: 50 },
      { videoUrl: 'https://www.bilibili.com/video/BV1hi', title: '红烧肉做法', provider: 'bilibili', play: 50000 },
    ] });
    const rep = await acquireMissingVideos(recipes, { search, now: 't', minPlay: 1000 });
    expect(rep.acquired).toBe(1);
    expect(recipes[0].videoUrl).toBe('https://www.bilibili.com/video/BV1hi'); // 跳过低播放,取达标的
    expect(recipes[1].videoUrl).toBeNull();
    expect(rep.attributions[0]).toMatchObject({ id: 'a', provider: 'bilibili', videoUrl: 'https://www.bilibili.com/video/BV1hi' });
  });
  it('既有 videoUrl 跳过(既有优先);软删跳过', async () => {
    const recipes = [
      r({ id: 'a', name: '红烧肉', videoUrl: 'https://old' }),
      r({ id: 'c', name: '红烧肉', deletedAt: '2026-01-01T00:00:00Z' }),
    ];
    const search = stub({ '红烧肉': [{ videoUrl: 'https://www.bilibili.com/video/BV1x', title: 't', provider: 'bilibili', play: 99999 }] });
    const rep = await acquireMissingVideos(recipes, { search, now: 't' });
    expect(rep.acquired).toBe(0);
    expect(recipes[0].videoUrl).toBe('https://old');
  });
});

describe('mergeVideoAttributions', () => {
  it('按 id 合并(新覆盖旧)并按 id 排序', () => {
    const prev: VideoAttribution[] = [{ id: 'b', name: 'B', videoUrl: 'u_b_old', acquiredAt: 't' }];
    const next: VideoAttribution[] = [
      { id: 'a', name: 'A', videoUrl: 'u_a', acquiredAt: 't' },
      { id: 'b', name: 'B', videoUrl: 'u_b_new', acquiredAt: 't' },
    ];
    const merged = mergeVideoAttributions(prev, next);
    expect(merged.map((m) => m.id)).toEqual(['a', 'b']);
    expect(merged.find((m) => m.id === 'b')!.videoUrl).toBe('u_b_new');
  });
});
