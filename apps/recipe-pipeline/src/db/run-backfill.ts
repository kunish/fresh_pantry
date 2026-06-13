import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyBackfill, type RecipeCorrections } from '../clean/backfill';
import { validateCleanRecipe } from '../clean/validate';
import { rawFromMarkdown } from '../sources/howtocook';
import { atomicWriteJson } from '../util/atomic-write';
import type { CleanRecipe } from '../clean/schema';
import { config } from '../config';

/**
 * 应用「缺量食材用量回填」(`npx tsx src/db/run-backfill.ts <corrections.json>`)。
 *
 * 流程:读多代理抽取+对抗校验后的修正 → applyBackfill 回填(数字回填/源无数字落「适量」)
 * → 对每条改动菜谱用 rawFromMarkdown 还原源、validateCleanRecipe 重过「无损数字 schema」
 * 质量闸门(尤其用量数字必须能在源文本溯源)→ 全绿才原子写回 howtocook.json。
 * 任一菜谱仍有违规即中止、落 violations 文件、不写盘,避免污染权威目录。
 */

const here = dirname(fileURLToPath(import.meta.url));
const cacheDir = resolve(here, '../../.cache');
const correctionsPath = process.argv[2] ?? resolve(cacheDir, 'backfill-corrections.json');
const violationsPath = resolve(cacheDir, 'backfill-violations.json');

const corrections = JSON.parse(readFileSync(correctionsPath, 'utf8')) as RecipeCorrections[];
const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];

const { recipes: applied, report } = applyBackfill(recipes, corrections);

// 改动菜谱集合(收到修正的 id),逐条对源重过质量闸门
const changedIds = new Set(corrections.map((c) => c.id));
const repoDir = resolve(cacheDir, 'howtocook');
const failures: Array<{ id: string; violations: string[] }> = [];
for (const r of applied) {
  if (!changedIds.has(r.id) || !r.id.startsWith('howtocook:')) continue;
  const rel = r.id.replace('howtocook:', '');
  const md = readFileSync(resolve(repoDir, 'dishes', `${rel}.md`), 'utf8');
  const raw = rawFromMarkdown(`dishes/${rel}.md`, md);
  const violations = validateCleanRecipe(r, raw);
  if (violations.length) failures.push({ id: r.id, violations });
}

console.log(
  `回填: amount=${report.amountsApplied} 适量=${report.fuzzyMarked} `
  + `已带量未动=${report.alreadyQuantified} 未采用修正=${report.unmatched}`,
);

if (failures.length) {
  await atomicWriteJson(violationsPath, failures);
  console.error(`❌ ${failures.length} 条菜谱仍违反质量闸门,已中止写盘。详见 ${violationsPath}`);
  for (const f of failures.slice(0, 10)) console.error(`  - ${f.id}: ${f.violations.join('; ')}`);
  process.exit(1);
}

await atomicWriteJson(config.outPath, applied);
console.log(`✅ 全部通过质量闸门,已写回 ${config.outPath}(${applied.length} 条)`);
