import type { CleanRecipe } from './schema';
import type { DishQuery, Log } from './fetch-images';

/**
 * 菜谱视频:pipeline 自带确定性视频搜集(免 key 的 B站 provider)。
 * 镜像 `fetch-images.ts` 的 acquireMissingImages 模式——为缺视频的菜谱联网搜一条做法视频外链,
 * 就地写 videoUrl,并产出可溯源出处。视频不下载、不托管,只存外链。
 */

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

/** 一条候选视频(B站等搜索源产出)。 */
export interface VideoCandidate {
  videoUrl: string;       // 观看页 URL
  title: string;
  provider: string;       // bilibili / youtube / …
  sourcePage?: string;
  author?: string;
  play?: number;          // 播放量(质量/反垃圾信号)
  durationSec?: number;
}

export interface VideoSearchProvider {
  /** 返回候选视频(按相关度降序);无结果返回空数组,绝不抛。 */
  search(dish: DishQuery, log: Log): Promise<VideoCandidate[]>;
}

export interface AcquireVideoDeps {
  search: VideoSearchProvider;
  now: string;
  /** 候选最低播放量门槛(反垃圾),默认 1000。 */
  minPlay?: number;
  log?: Log;
}

export interface AcquireVideoReport {
  acquired: number;
  failed: number;
  skipped: number;
  attributions: VideoAttribution[];
  failures: { id: string; name: string }[];
}

/**
 * 为缺视频的菜谱联网搜一条做法视频外链(就地写 videoUrl)。已有视频/软删跳过(既有优先);
 * 取首个达到播放阈值的候选(信任搜索相关度,过滤低播放垃圾);搜不到留 null,诚实不硬塞。
 */
export async function acquireMissingVideos(
  recipes: CleanRecipe[],
  deps: AcquireVideoDeps,
): Promise<AcquireVideoReport> {
  const log = deps.log ?? (() => {});
  const minPlay = deps.minPlay ?? 1000;
  const report: AcquireVideoReport = { acquired: 0, failed: 0, skipped: 0, attributions: [], failures: [] };
  for (const r of recipes) {
    if (!needsVideo(r)) { report.skipped++; continue; }
    const dish: DishQuery = {
      id: r.id, name: r.name, category: r.category,
      ingredients: r.ingredients.map((i) => i.name).slice(0, 6),
    };
    const candidates = await deps.search.search(dish, log).catch(() => []);
    const pick = candidates.find((c) => /^https?:\/\//.test(c.videoUrl) && (c.play ?? 0) >= minPlay) ?? null;
    if (!pick) {
      report.failed++; report.failures.push({ id: r.id, name: r.name });
      log(`未找到合适视频,留空: ${r.id}`);
      continue;
    }
    r.videoUrl = pick.videoUrl;
    report.acquired++;
    report.attributions.push({
      id: r.id, name: r.name, videoUrl: pick.videoUrl,
      sourcePage: pick.sourcePage ?? pick.videoUrl, title: pick.title,
      provider: pick.provider, acquiredAt: deps.now,
    });
    log(`视频已补: ${r.id} ← ${pick.videoUrl}`);
  }
  return report;
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
