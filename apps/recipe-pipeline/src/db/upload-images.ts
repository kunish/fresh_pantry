import { readdirSync, readFileSync } from 'node:fs';
import { join, extname } from 'node:path';
import { mapWithConcurrency } from '../util/pool';
import { storageKeyFor } from './storage-key';
import { config } from '../config';

/**
 * 把 app bundle 的 RecipeImages/ 全量上传到 Supabase Storage 的 `recipe-images`
 * 公共桶(发版后封面全部走 Supabase + iOS 磁盘缓存,不再随包打包 ~111MB)。
 *
 * 用 tsx 直跑:
 *   SUPABASE_URL=… SUPABASE_KEY=<publishable/service key> npx tsx src/db/upload-images.ts
 *
 * 幂等(x-upsert:true),可重复跑补传失败项。桶默认无写策略,上传需:
 *   - service_role key(绕 RLS),或
 *   - 上传窗口临时给 anon 开 INSERT 策略(配 publishable key),传完锁回(见 README)。
 */
const BUCKET = 'recipe-images';

const SUPABASE_URL = (process.env.SUPABASE_URL ?? '').replace(/\/+$/, '');
const SUPABASE_KEY = process.env.SUPABASE_KEY ?? '';
if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('缺 SUPABASE_URL / SUPABASE_KEY 环境变量');
  process.exit(1);
}

function mimeFor(file: string): string | null {
  switch (extname(file).toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    default:
      return null;
  }
}

async function uploadOne(file: string): Promise<'ok' | 'skip' | 'fail'> {
  const mime = mimeFor(file);
  if (!mime) return 'skip';
  const body = readFileSync(join(config.imagesDir, file));
  const url = `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${storageKeyFor(file)}`;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${SUPABASE_KEY}`,
          apikey: SUPABASE_KEY,
          'Content-Type': mime,
          'x-upsert': 'true',
          'cache-control': 'public, max-age=31536000, immutable',
        },
        body,
      });
      if (res.ok) return 'ok';
      const text = await res.text().catch(() => '');
      if (attempt === 3) {
        console.error(`✗ ${file} → ${res.status} ${text.slice(0, 160)}`);
        return 'fail';
      }
    } catch (err) {
      if (attempt === 3) {
        console.error(`✗ ${file} → ${err instanceof Error ? err.message : String(err)}`);
        return 'fail';
      }
    }
    await new Promise((r) => setTimeout(r, 400 * attempt));
  }
  return 'fail';
}

const files = readdirSync(config.imagesDir).filter((f) => mimeFor(f) !== null).sort();
console.log(`上传 ${files.length} 张到 ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/ …`);

const results = await mapWithConcurrency(files, 6, uploadOne);
const ok = results.filter((r) => r === 'ok').length;
const fail = results.filter((r) => r === 'fail').length;
const skip = results.filter((r) => r === 'skip').length;
console.log(`完成:成功 ${ok}、失败 ${fail}、跳过 ${skip}`);
if (fail) process.exit(2);
