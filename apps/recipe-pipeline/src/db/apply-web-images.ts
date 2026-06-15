import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { atomicWriteJson } from '../util/atomic-write';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  applyAcquiredImages, mergeAttributions,
  type AcquiredImage, type Attribution,
} from '../clean/fetch-images';
import type { CleanRecipe } from '../clean/schema';
import { config } from '../config';

/**
 * 把 ultracode「联网补图」workflow 的产物回写进 howtocook.json。
 * 用 tsx 直跑:`npx tsx src/db/apply-web-images.ts`。
 *
 * workflow 的每个 agent 把图落进 RecipeImages/,并把这一条的结果写成
 * data/acquired/<index>.json。本脚本聚合这些小文件,经已测纯函数
 * `applyAcquiredImages` 给仍缺图的菜谱回填 imageUrl,并把来源合并进
 * data/image-attributions.json(出处可溯源)。重跑后 `npm run gen:seed` 同步 DB 种子。
 */
const here = dirname(fileURLToPath(import.meta.url));
const acquiredDir = resolve(here, '../../data/acquired');

interface MetaFile {
  index?: number;
  id?: string;
  ok?: boolean;
  file?: string | null;
  sourceUrl?: string | null;
  sourcePage?: string | null;
  license?: string | null;
  confidence?: string | null;
  reason?: string;
}

function readMetaFiles(): MetaFile[] {
  const metas: MetaFile[] = [];
  for (const name of readdirSync(acquiredDir)) {
    if (!/^\d+\.json$/.test(name)) continue; // 只收 <index>.json,跳过 _dishes.json 等
    try {
      metas.push(JSON.parse(readFileSync(join(acquiredDir, name), 'utf8')) as MetaFile);
    } catch {
      console.warn(`跳过损坏的 meta: ${name}`);
    }
  }
  return metas;
}

const metas = readMetaFiles();
const okMetas = metas.filter((m) => m.ok && m.id && m.file);

// 只采纳「图文件真实落盘」的条目,防 agent 自报 ok 但 cp 失败的幽灵记录。
const acquired: AcquiredImage[] = [];
const missingFiles: string[] = [];
for (const m of okMetas) {
  if (existsSync(join(config.imagesDir, m.file!))) {
    acquired.push({
      id: m.id!, file: m.file!,
      sourceUrl: m.sourceUrl ?? '', sourcePage: m.sourcePage ?? undefined,
      license: m.license ?? undefined,
    });
  } else {
    missingFiles.push(`${m.id} → ${m.file}(文件不在 RecipeImages/)`);
  }
}

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
const now = new Date().toISOString();
const { updated, attributions } = applyAcquiredImages(recipes, acquired, now);

await atomicWriteJson(config.outPath, recipes);

const prevAttr: Attribution[] = existsSync(config.attributionsPath)
  ? (JSON.parse(readFileSync(config.attributionsPath, 'utf8')) as Attribution[])
  : [];
const mergedAttr = mergeAttributions(prevAttr, attributions);
writeFileSync(config.attributionsPath, JSON.stringify(mergedAttr, null, 2) + '\n', 'utf8');

const stillMissing = recipes.filter((r) => (r.imageUrl === null || r.imageUrl === '') && !r.deletedAt).length;
console.log(`apply-web-images:`);
console.log(`  meta 文件 ${metas.length} 条,其中 ok ${okMetas.length} 条,落盘验证通过 ${acquired.length} 条`);
console.log(`  回写 imageUrl ${updated} 条 → ${config.outPath}`);
console.log(`  出处累计 ${mergedAttr.length} 条 → ${config.attributionsPath}`);
console.log(`  仍缺图 ${stillMissing} 条`);
if (missingFiles.length) {
  console.warn(`  ⚠️ ${missingFiles.length} 条自报 ok 但图文件缺失,已忽略:`);
  for (const x of missingFiles) console.warn(`    - ${x}`);
}
