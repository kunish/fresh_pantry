import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isTool } from '../parse/howtocook-parser';
import { validateCleanRecipe } from '../clean/validate';
import { rawFromMarkdown } from '../sources/howtocook';
import { atomicWriteJson } from '../util/atomic-write';
import type { CleanRecipe } from '../clean/schema';
import { config } from '../config';

/**
 * 从清洗后菜谱里剔除「混入食材列表的厨具」(`npx tsx src/db/strip-tools.ts`)。
 *
 * 历史数据缺陷:HowToCook 源「必备原料和工具」段把器具(面包机/量酒器/烤网/汤匙…)
 * 与食材并列,早期 `isTool` 关键词不全致器具落进 ingredients。本脚本用**改进后的
 * 管线 `isTool`**(单一事实源)把它们滤掉,再对源重过 `validateCleanRecipe` 质量闸门
 * (该闸门本就有「工具混入食材」检查,剔除后归零),全绿才原子写回 howtocook.json。
 */

const here = dirname(fileURLToPath(import.meta.url));
const cacheDir = resolve(here, '../../.cache');
const repoDir = resolve(cacheDir, 'howtocook');

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];

let removed = 0;
const removedByRecipe: Array<{ id: string; tools: string[] }> = [];
const cleaned = recipes.map((r) => {
  const tools = r.ingredients.filter((i) => isTool(i.name)).map((i) => i.name);
  if (!tools.length) return r;
  removed += tools.length;
  removedByRecipe.push({ id: r.id, tools });
  return { ...r, ingredients: r.ingredients.filter((i) => !isTool(i.name)) };
});

const failures: Array<{ id: string; violations: string[] }> = [];
for (const { id } of removedByRecipe) {
  if (!id.startsWith('howtocook:')) continue;
  const rel = id.replace('howtocook:', '');
  const md = readFileSync(resolve(repoDir, 'dishes', `${rel}.md`), 'utf8');
  const raw = rawFromMarkdown(`dishes/${rel}.md`, md);
  const recipe = cleaned.find((r) => r.id === id)!;
  const violations = validateCleanRecipe(recipe, raw);
  if (violations.length) failures.push({ id, violations });
}

console.log(`剔除工具: ${removed} 个,涉及 ${removedByRecipe.length} 道菜`);
for (const { id, tools } of removedByRecipe) console.log(`  - ${id.replace('howtocook:', '')}: ${tools.join('、')}`);

if (failures.length) {
  console.error(`❌ ${failures.length} 条菜谱剔除后仍违反质量闸门,已中止写盘:`);
  for (const f of failures) console.error(`  - ${f.id}: ${f.violations.join('; ')}`);
  process.exit(1);
}

await atomicWriteJson(config.outPath, cleaned);
console.log(`✅ 全部通过质量闸门,已写回 ${config.outPath}(${cleaned.length} 条)`);
