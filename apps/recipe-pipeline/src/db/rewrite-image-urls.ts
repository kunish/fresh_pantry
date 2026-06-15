import { readFileSync } from 'node:fs';
import type { CleanRecipe } from '../clean/schema';
import { storageKeyFor } from './storage-key';
import { config } from '../config';
import { atomicWriteJson } from '../util/atomic-write';

/**
 * 把 howtocook.json 里 `assets/recipes/images/<file>` 形态的 imageUrl 改写为
 * Supabase Storage 的公共 URL(发版后封面全部走 Supabase + iOS 磁盘缓存)。
 * 改写后 `gen:seed` 生成的 recipes.image_url、以及 iOS 内置离线 seed 都带 Supabase URL。
 *
 *   SUPABASE_URL=https://<ref>.supabase.co npx tsx src/db/rewrite-image-urls.ts
 *
 * 幂等:已是 http(s) 的 URL、null 都原样保留;只转 assets/ 前缀的本地路径。
 * 项目 URL 是公开 API 端点(每个 app 内置),写进目录数据无密钥泄露。
 */
const BUCKET = 'recipe-images';
const ASSETS_PREFIX = 'assets/recipes/images/';

const base = (process.env.SUPABASE_URL ?? '').replace(/\/+$/, '');
if (!base) {
  console.error('缺 SUPABASE_URL 环境变量(如 https://<ref>.supabase.co)');
  process.exit(1);
}
const publicBase = `${base}/storage/v1/object/public/${BUCKET}/`;

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
let rewritten = 0;
let alreadyRemote = 0;
for (const r of recipes) {
  const u = r.imageUrl;
  if (!u) continue;
  if (u.startsWith(ASSETS_PREFIX)) {
    const file = u.slice(ASSETS_PREFIX.length);
    r.imageUrl = publicBase + storageKeyFor(file);
    rewritten++;
  } else if (/^https?:\/\//.test(u)) {
    alreadyRemote++;
  }
}

await atomicWriteJson(config.outPath, recipes);
console.log(`rewrite-image-urls: 改写 ${rewritten} 条 → ${publicBase}…  已是远程 ${alreadyRemote} 条`);
console.log(`  示例: ${recipes.find((r) => r.imageUrl?.startsWith(base))?.imageUrl ?? '(无)'}`);
