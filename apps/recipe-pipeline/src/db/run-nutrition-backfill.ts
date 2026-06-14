import { readFileSync } from 'node:fs';
import { createCloudflareEnricher } from '../clean/cloudflare-enricher';
import { assembleRecipe } from '../clean/enrich';
import { atomicWriteJson } from '../util/atomic-write';
import { config } from '../config';
import type { CleanRecipe, Ingredient } from '../clean/schema';
import type { RawRecipe } from '../sources/types';

/**
 * 给现有 howtocook.json 全量补「每份营养 + 每步时长」(P2/P3),不重清洗其他字段。
 *
 * 对每条菜谱用现有 name/category/steps/ingredients 构造 raw → Cloudflare Kimi enrich
 * → 只取 nutrition + stepDurations 写回(用量/步骤/标签/描述保持现有 deepseek 清洗版
 * 不变)。比整条重清洗安全:不受用量闸门 reject 影响、不回退已清洗的用量质量、全覆盖。
 *
 *   npx tsx --env-file=.env src/db/run-nutrition-backfill.ts
 *   env: BACKFILL_LIMIT=N(只处理前 N 条)、BACKFILL_DRY=1(不写盘,打印样例)。
 */

const LIMIT = process.env.BACKFILL_LIMIT ? Number(process.env.BACKFILL_LIMIT) : Infinity;
const DRY = process.env.BACKFILL_DRY === '1';

/** 食材显示用量(供 LLM 据此估营养):有数字→「<q>[-<max>]<unit>」,否则 note/unit。 */
function amountText(i: Ingredient): string {
  if (i.quantity != null) {
    const base = i.quantityMax != null ? `${i.quantity}-${i.quantityMax}` : `${i.quantity}`;
    return base + (i.unit ?? '');
  }
  return i.note ?? i.unit ?? '';
}

/** 把现有清洗后的菜谱还原成 enrich 的输入(steps/ingredients 原样,带用量供估营养)。 */
function rawFromRecipe(r: CleanRecipe): RawRecipe {
  return {
    id: r.id, sourceId: 'backfill', sourceRef: r.id, name: r.name,
    sourceCategory: r.category, sourceDifficulty: r.difficulty, sourceCookingMinutes: r.cookingMinutes,
    description: r.description,
    rawIngredients: r.ingredients.map((i) => i.name),
    portionText: r.ingredients.map((i) => `${i.name} ${amountText(i)}`.trim()).join('\n'),
    steps: r.steps,
    imageUrl: r.imageUrl,
  };
}

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
const enricher = createCloudflareEnricher({
  baseUrl: config.cloudflare.baseUrl, apiKey: config.cloudflare.apiKey,
  model: config.model, maxTokens: config.cloudflare.maxTokens, log: () => {},
});

const targets = recipes.slice(0, LIMIT === Infinity ? recipes.length : LIMIT);
let done = 0, withNutrition = 0, withDurations = 0, failed = 0;
const concurrency = config.concurrency;

async function worker(slice: CleanRecipe[]): Promise<void> {
  for (const r of slice) {
    try {
      const raw = rawFromRecipe(r);
      const enr = await enricher.enrich(raw);
      const a = assembleRecipe(raw, enr);
      // 只取这两个新字段写回(步骤时长已在 assembleRecipe 对齐现有 steps)。
      if (a.nutrition) { r.nutrition = a.nutrition; withNutrition++; }
      if (a.stepDurations) { r.stepDurations = a.stepDurations; withDurations++; }
    } catch (e) {
      failed++;
      console.error(`[backfill] ✗ ${r.name}: ${e instanceof Error ? e.message : e}`);
    }
    done++;
    if (done % 20 === 0) {
      console.error(`[backfill] ${done}/${targets.length} (营养 ${withNutrition} / 时长 ${withDurations} / 失败 ${failed})`);
    }
  }
}

const chunks: CleanRecipe[][] = Array.from({ length: concurrency }, () => []);
targets.forEach((r, i) => chunks[i % concurrency].push(r));
await Promise.all(chunks.map(worker));

console.error(`[backfill] 完成 ${done}/${targets.length}: 营养 ${withNutrition}, 时长 ${withDurations}, 失败 ${failed}`);
if (DRY) {
  console.error('[backfill] DRY(不写盘)样例:\n', JSON.stringify(
    targets.slice(0, 3).map((r) => ({ name: r.name, nutrition: r.nutrition, stepDurations: r.stepDurations })),
    null, 2,
  ));
} else {
  await atomicWriteJson(config.outPath, recipes);
  console.error(`[backfill] 已原子写回 ${config.outPath}`);
}
