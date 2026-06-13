import type { CleanRecipe } from './schema';

/**
 * 菜谱视频:外链 URL。镜像 `fetch-images.ts` 的 applyAcquiredImages/mergeAttributions——
 * ultracode「联网搜视频」workflow 每菜产出一条 {id, videoUrl, …},本模块纯函数把
 * videoUrl 回写进仍缺视频的菜谱(既有优先),并产出可溯源出处。视频不下载、不托管,只存外链。
 */

/** workflow agent 回传的一条视频结果(视频是外链,无文件落盘)。 */
export interface AcquiredVideo {
  id: string;
  videoUrl: string;
  sourcePage?: string;
  title?: string;
  provider?: string; // bilibili / youtube / xiachufang / …
}

/** 出处记录,持久化到 `data/video-attributions.json`。 */
export interface VideoAttribution {
  id: string;
  name: string;
  videoUrl: string;
  sourcePage?: string;
  title?: string;
  provider?: string;
  acquiredAt: string;
}

/** 待补视频:没视频、且非软删。 */
function needsVideo(r: CleanRecipe): boolean {
  return (r.videoUrl === null || r.videoUrl === '') && !r.deletedAt;
}

/**
 * 纯函数:把搜到的外链回写进仍缺视频的菜谱 videoUrl(既有优先,软删跳过),并产出出处。
 */
export function applyAcquiredVideos(
  recipes: CleanRecipe[],
  acquired: AcquiredVideo[],
  now: string,
): { updated: number; attributions: VideoAttribution[] } {
  const byId = new Map(acquired.map((a) => [a.id, a]));
  let updated = 0;
  const attributions: VideoAttribution[] = [];
  for (const r of recipes) {
    const a = byId.get(r.id);
    if (!a || !a.videoUrl) continue;
    if (!needsVideo(r)) continue; // 既有优先
    r.videoUrl = a.videoUrl;
    updated++;
    attributions.push({
      id: r.id, name: r.name, videoUrl: a.videoUrl,
      sourcePage: a.sourcePage, title: a.title, provider: a.provider, acquiredAt: now,
    });
  }
  return { updated, attributions };
}

/** 出处按 id 合并(新覆盖旧),稳定按 id 排序便于 diff。 */
export function mergeVideoAttributions(
  prev: VideoAttribution[],
  next: VideoAttribution[],
): VideoAttribution[] {
  const byId = new Map(prev.map((a) => [a.id, a]));
  for (const a of next) byId.set(a.id, a);
  return [...byId.values()].sort((x, y) => x.id.localeCompare(y.id));
}
