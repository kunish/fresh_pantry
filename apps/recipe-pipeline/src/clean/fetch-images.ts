import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { CleanRecipe } from './schema';

/**
 * 联网补封面:HowToCook 上游约半数家常菜本就没图,本阶段为 `imageUrl === null`
 * 的菜谱联网搜一张「合适的成品图」,逐张做图像内容校验,下载进 app bundle
 * (`assets/recipes/images/`,离线可用、零外链),并把来源记进 attribution 以便溯源。
 *
 * 搜索与校验都藏在注入接口后(`ImageSearchProvider` / `ImageVerifier`):
 * - 管线内置默认走免 key 的来源(见 `src/sources/image-search-openverse.ts`);
 * - 全网最佳匹配 + 多模态视觉校验由 ultracode workflow 的 agent 充当 provider,
 *   产物经 `applyAcquiredImages` 以同一格式回写,两条路径完全一致。
 */

export const ASSETS_PREFIX = 'assets/recipes/images/';

export type Log = (msg: string) => void;

/** 喂给搜索/校验的菜谱信息(够消歧:名字 + 分类 + 几样主料)。 */
export interface DishQuery {
  id: string;
  name: string;
  category: string;
  ingredients?: string[];
}

/** 一条候选图:直链 + 可选来源页/标题/许可,用于下载与出处记录。 */
export interface ImageCandidate {
  url: string;
  sourcePage?: string;
  title?: string;
  license?: string;
}

export interface ImageSearchProvider {
  /** 返回候选图(按相关度降序);无结果返回空数组,绝不抛。 */
  search(dish: DishQuery, log: Log): Promise<ImageCandidate[]>;
}

export interface VerifyResult {
  ok: boolean;
  reason?: string;
}

export interface ImageVerifier {
  /** 判断图像内容确为该菜品的洁净食物照(无水印/拼图/人物/文字海报、分辨率够)。 */
  verify(image: Buffer, dish: DishQuery): Promise<VerifyResult>;
}

/** 落盘后的出处记录,持久化到 `data/image-attributions.json`。 */
export interface Attribution {
  id: string;
  name: string;
  file: string;
  sourceUrl: string;
  sourcePage?: string;
  title?: string;
  license?: string;
  acquiredAt: string;
}

export interface AcquireDeps {
  /** app bundle 的 RecipeImages 目录(folder reference)。 */
  imagesDir: string;
  search: ImageSearchProvider;
  /** 缺省=只校验是真图;提供则逐张做内容校验(确为该菜)。 */
  verify?: ImageVerifier;
  /** 下载真图;失败返回 null。注入以便测试 mock。 */
  fetchImage: (url: string) => Promise<Buffer | null>;
  now: string;
  /** 每道菜最多试几张候选,默认 5。 */
  maxCandidates?: number;
  log?: Log;
}

export interface AcquireReport {
  acquired: number;
  failed: number;
  skipped: number;
  attributions: Attribution[];
  failures: { id: string; name: string }[];
}

/** 图像 magic bytes → 扩展名;非图片(HTML/LFS pointer/文本)返回 null。 */
export function imageExtFromBuffer(buf: Buffer): string | null {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return '.jpg';
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return '.png';
  if (buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x38) return '.gif';
  if (
    buf.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buf.subarray(8, 12).toString('ascii') === 'WEBP'
  ) {
    return '.webp';
  }
  return null;
}

/** 联网图统一命名:`web_<id 去 source 前缀、/换_>.<ext>`,与 howtocook_ 前缀区分开。 */
export function webImageName(id: string, ext: string): string {
  const idPath = id.replace(/^[^:]+:/, '').replace(/\//g, '_');
  return `web_${idPath}${ext}`;
}

/** 待补图的菜谱:没图、且不是软删条目。 */
function needsImage(r: CleanRecipe): boolean {
  return (r.imageUrl === null || r.imageUrl === '') && !r.deletedAt;
}

/**
 * 为缺图菜谱联网补封面(就地改 `recipes` 的 imageUrl,写盘进 imagesDir)。
 * 已有图的条目原样跳过;搜不到/全部校验不过的留 null(下次再试),诚实不硬塞。
 */
export async function acquireMissingImages(
  recipes: CleanRecipe[],
  deps: AcquireDeps,
): Promise<AcquireReport> {
  const log = deps.log ?? (() => {});
  const maxCandidates = deps.maxCandidates ?? 5;
  const report: AcquireReport = {
    acquired: 0, failed: 0, skipped: 0, attributions: [], failures: [],
  };

  for (const r of recipes) {
    if (!needsImage(r)) { report.skipped++; continue; }
    const dish: DishQuery = {
      id: r.id, name: r.name, category: r.category,
      ingredients: r.ingredients.map((i) => i.name).slice(0, 6),
    };

    const candidates = await deps.search.search(dish, log).catch(() => []);
    let done = false;
    for (const cand of candidates.slice(0, maxCandidates)) {
      const buf = await deps.fetchImage(cand.url).catch(() => null);
      if (!buf) continue;
      const ext = imageExtFromBuffer(buf);
      if (!ext) continue; // HTML 错误页 / 文本 / 非图片体,跳过
      if (deps.verify) {
        const verdict = await deps.verify.verify(buf, dish).catch(() => ({ ok: false }));
        if (!verdict.ok) continue;
      }
      const file = webImageName(r.id, ext);
      await writeFile(join(deps.imagesDir, file), buf);
      r.imageUrl = ASSETS_PREFIX + file;
      report.acquired++;
      report.attributions.push({
        id: r.id, name: r.name, file,
        sourceUrl: cand.url, sourcePage: cand.sourcePage,
        title: cand.title, license: cand.license, acquiredAt: deps.now,
      });
      log(`封面已补: ${r.id} ← ${cand.url}`);
      done = true;
      break;
    }
    if (!done) {
      report.failed++;
      report.failures.push({ id: r.id, name: r.name });
      log(`未找到合适封面,留空下次再试: ${r.id}`);
    }
  }
  return report;
}

/** workflow agent 落好图后回传的元数据(图文件已在 imagesDir,这里只回写 json)。 */
export interface AcquiredImage {
  id: string;
  file: string;
  sourceUrl: string;
  sourcePage?: string;
  title?: string;
  license?: string;
}

/**
 * 纯函数:把已落盘的联网图回写进菜谱的 imageUrl(只动仍缺图的条目),
 * 并产出 attribution。ultracode workflow 跑完后由主流程调用,与管线内阶段同格式。
 */
export function applyAcquiredImages(
  recipes: CleanRecipe[],
  acquired: AcquiredImage[],
  now: string,
): { updated: number; attributions: Attribution[] } {
  const byId = new Map(acquired.map((a) => [a.id, a]));
  let updated = 0;
  const attributions: Attribution[] = [];
  for (const r of recipes) {
    const a = byId.get(r.id);
    if (!a) continue;
    if (!needsImage(r)) continue; // 已有图不覆盖(既有优先)
    r.imageUrl = ASSETS_PREFIX + a.file;
    updated++;
    attributions.push({
      id: r.id, name: r.name, file: a.file,
      sourceUrl: a.sourceUrl, sourcePage: a.sourcePage,
      title: a.title, license: a.license, acquiredAt: now,
    });
  }
  return { updated, attributions };
}

/** 出处记录按 id 合并(新覆盖旧),稳定按 id 排序便于 diff。 */
export function mergeAttributions(
  prev: Attribution[],
  next: Attribution[],
): Attribution[] {
  const byId = new Map(prev.map((a) => [a.id, a]));
  for (const a of next) byId.set(a.id, a);
  return [...byId.values()].sort((x, y) => x.id.localeCompare(y.id));
}
