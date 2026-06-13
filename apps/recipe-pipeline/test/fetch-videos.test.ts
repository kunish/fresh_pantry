import { describe, it, expect } from 'vitest';
import { applyAcquiredVideos, mergeVideoAttributions, type VideoAttribution } from '../src/clean/fetch-videos';
import type { CleanRecipe } from '../src/clean/schema';

const r = (over: Partial<CleanRecipe> = {}): CleanRecipe => ({
  id: 'r1', name: '番茄炒蛋', category: '荤菜', difficulty: 1, cookingMinutes: 10,
  description: 'd', ingredients: [], steps: [], tags: [], imageUrl: null,
  videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
});

describe('applyAcquiredVideos', () => {
  it('给缺视频的菜回填 videoUrl + 产出出处', () => {
    const recipes = [r({ id: 'a' }), r({ id: 'b' })];
    const { updated, attributions } = applyAcquiredVideos(
      recipes,
      [{ id: 'a', videoUrl: 'https://b23.tv/a', provider: 'bilibili', title: 'A 做法' }],
      '2026-06-13T00:00:00Z',
    );
    expect(updated).toBe(1);
    expect(recipes[0].videoUrl).toBe('https://b23.tv/a');
    expect(recipes[1].videoUrl).toBeNull();
    expect(attributions[0]).toMatchObject({ id: 'a', videoUrl: 'https://b23.tv/a', provider: 'bilibili' });
  });
  it('既有 videoUrl 不覆盖;空 videoUrl 的 acquired 跳过;软删跳过', () => {
    const recipes = [r({ id: 'a', videoUrl: 'https://old' }), r({ id: 'c', deletedAt: '2026-01-01T00:00:00Z' })];
    const { updated } = applyAcquiredVideos(
      recipes,
      [{ id: 'a', videoUrl: 'https://new' }, { id: 'c', videoUrl: 'https://x' }, { id: 'd', videoUrl: '' }],
      '2026-06-13T00:00:00Z',
    );
    expect(updated).toBe(0);
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
