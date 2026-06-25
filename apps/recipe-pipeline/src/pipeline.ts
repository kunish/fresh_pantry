import { readFile, rm } from 'node:fs/promises';
import * as v from 'valibot';
import type { RecipeSource, RawRecipe, SourceContext } from './sources/types';
import type { RecipeEnricher } from './clean/enrich';
import { assembleRecipe } from './clean/enrich';
import { CleanRecipeSchema, type CleanRecipe } from './clean/schema';
import { validateCleanRecipe } from './clean/validate';
import { dedupe } from './clean/dedup';
import { mergeWithExisting, type MergeOptions } from './clean/merge';
import { vendorRemoteImages, fetchImageBuffer } from './clean/vendor-images';
import {
  acquireMissingImages, mergeAttributions,
  type ImageSearchProvider, type ImageVerifier, type Attribution,
} from './clean/fetch-images';
import {
  acquireMissingVideos, mergeVideoAttributions,
  type VideoAttribution, type VideoSearchProvider,
} from './clean/fetch-videos';
import { mapWithConcurrency } from './util/pool';
import { atomicWriteJson } from './util/atomic-write';

export interface PipelineDeps extends MergeOptions {
  sources: RecipeSource[];
  enricher: RecipeEnricher;
  existingPath: string;
  outPath: string;
  rejectsPath: string;
  now: string;
  workDir?: string;
  /** app bundle 的 RecipeImages 目录;设置后远程封面会被 vendor 成 assets/ 路径。 */
  imagesDir?: string;
  /** 测试注入;缺省走真实网络下载。 */
  fetchImage?: (url: string) => Promise<Buffer | null>;
  /** 设置则为仍缺图(imageUrl=null)的菜谱联网补封面(vendor 之前)。 */
  imageSearch?: ImageSearchProvider;
  /** 逐张图像内容校验(确为该菜);缺省只校验是真图。 */
  imageVerifier?: ImageVerifier;
  /** 出处记录落盘路径(image-attributions.json);缺省不持久化。 */
  attributionsPath?: string;
  /** 设置则为缺视频(videoUrl=null)的菜谱联网搜做法视频外链。 */
  videoSearch?: VideoSearchProvider;
  /** 视频出处落盘路径(video-attributions.json);缺省不持久化。 */
  videoAttributionsPath?: string;
  concurrency?: number;
  limit?: number;
  /** 只处理这些 id(单条补跑,如网络瞬断被拒的菜)。 */
  only?: string[];
  /** 跳过所有封面 acquire/vendor(只修文本字段时用,护住已迁 Storage 的 imageUrl 不被改写)。 */
  skipImages?: boolean;
  dryRun?: boolean;
  log?: (msg: string) => void;
}

export interface PipelineReport {
  collected: number;
  cleaned: number;
  rejected: number;
  deduped: number;
  added: number;
  updated: number;
  unchanged: number;
  acquiredImages: number;
  total: number;
}

interface Reject {
  id: string;
  name: string;
  sourceRef: string;
  error: string;
}

export async function runPipeline(deps: PipelineDeps): Promise<PipelineReport> {
  const log = deps.log ?? (() => {});
  const ctx: SourceContext = { workDir: deps.workDir ?? '.cache', log };

  const only = deps.only?.length ? new Set(deps.only) : null;
  const raws: RawRecipe[] = [];
  for (const src of deps.sources) {
    for await (const r of src.collect(ctx)) {
      if (only && !only.has(r.id)) continue;
      raws.push(r);
      if (deps.limit && raws.length >= deps.limit) break;
    }
    if (deps.limit && raws.length >= deps.limit) break;
  }
  log(`collected ${raws.length}`);

  const rejects: Reject[] = [];
  const cleanedNullable = await mapWithConcurrency(
    raws,
    deps.concurrency ?? 6,
    async (raw): Promise<CleanRecipe | null> => {
      try {
        const enr = await deps.enricher.enrich(raw);
        const assembled = assembleRecipe(raw, enr);
        const parsed = v.parse(CleanRecipeSchema, assembled);
        const violations = validateCleanRecipe(parsed, raw);
        if (violations.length) throw new Error(`质量闸门: ${violations.join('; ')}`);
        return parsed;
      } catch (err) {
        rejects.push({
          id: raw.id, name: raw.name, sourceRef: raw.sourceRef,
          error: err instanceof Error ? err.message : String(err),
        });
        return null;
      }
    },
  );
  const cleaned = cleanedNullable.filter((r): r is CleanRecipe => r !== null);
  log(`cleaned ${cleaned.length}, rejected ${rejects.length}`);

  const { kept, dropped } = dedupe(cleaned);
  log(`deduped: dropped ${dropped.length}`);

  const existingRaw = await readFile(deps.existingPath, 'utf8').catch((e: unknown) => {
    if ((e as NodeJS.ErrnoException).code === 'ENOENT') return '[]'; // 缺失=首次运行,空既有
    throw e;
  });
  let existing: CleanRecipe[];
  try {
    existing = JSON.parse(existingRaw) as CleanRecipe[];
  } catch {
    // 既有文件损坏:拒绝覆盖,避免用「仅新菜」抹掉已策展的 imageUrl/软删
    throw new Error(`既有菜谱文件 JSON 损坏,拒绝覆盖以保护数据: ${deps.existingPath}`);
  }
  const { merged, stats } = mergeWithExisting(kept, existing, {
    refreshDescriptions: deps.refreshDescriptions,
  });

  let acquiredImages = 0;
  if (deps.imagesDir && deps.imageSearch && !deps.dryRun && !deps.skipImages) {
    const acq = await acquireMissingImages(merged, {
      imagesDir: deps.imagesDir,
      search: deps.imageSearch,
      verify: deps.imageVerifier,
      fetchImage: deps.fetchImage ?? fetchImageBuffer,
      now: deps.now,
      log,
    });
    acquiredImages = acq.acquired;
    log(`acquired ${acq.acquired} web covers, ${acq.failed} still unmatched`);
    if (deps.attributionsPath && acq.attributions.length) {
      const prev = await readFile(deps.attributionsPath, 'utf8')
        .then((s) => JSON.parse(s) as Attribution[])
        .catch(() => [] as Attribution[]);
      await atomicWriteJson(deps.attributionsPath, mergeAttributions(prev, acq.attributions));
    }
  }

  if (deps.imagesDir && !deps.dryRun && !deps.skipImages) {
    const vendor = await vendorRemoteImages(merged, {
      imagesDir: deps.imagesDir,
      repoDir: `${ctx.workDir}/howtocook`,
      fetchImage: deps.fetchImage ?? fetchImageBuffer,
      log,
    });
    log(`vendored ${vendor.vendored} covers, ${vendor.kept} kept remote`);
  }

  if (deps.videoSearch && !deps.dryRun) {
    const vid = await acquireMissingVideos(merged, {
      search: deps.videoSearch, now: deps.now, log,
    });
    log(`acquired ${vid.acquired} videos, ${vid.failed} still missing`);
    if (deps.videoAttributionsPath && vid.attributions.length) {
      const prev = await readFile(deps.videoAttributionsPath, 'utf8')
        .then((s) => JSON.parse(s) as VideoAttribution[])
        .catch(() => [] as VideoAttribution[]);
      await atomicWriteJson(deps.videoAttributionsPath, mergeVideoAttributions(prev, vid.attributions));
    }
  }

  if (!deps.dryRun) {
    await atomicWriteJson(deps.outPath, merged);
    if (rejects.length) await atomicWriteJson(deps.rejectsPath, rejects);
    else await rm(deps.rejectsPath, { force: true }); // 零拒绝时清掉上轮残留,避免误导排查
  }

  return {
    collected: raws.length, cleaned: cleaned.length, rejected: rejects.length,
    deduped: dropped.length, added: stats.added, updated: stats.updated,
    unchanged: stats.unchanged, acquiredImages, total: merged.length,
  };
}
