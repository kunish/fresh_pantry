import { readFileSync } from 'node:fs';
import { config } from '../config';
import type { CleanRecipe } from '../clean/schema';

/**
 * 把 howtocook.json 的「每份营养 + 每步时长」灌进 prod public.recipes。
 *
 * 安全关键:**只 update nutrition / step_durations 两列**,绝不碰其他列——prod 现有
 * 的 video_url / ingredients / steps 等保持不动(全列 upsert 会用本地版覆盖,有清掉
 * prod 视频的风险)。走 Supabase Management API /database/query(token 由调用方经
 * keychain 注入 SUPABASE_ACCESS_TOKEN)。
 *
 *   export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
 *   npx tsx src/db/run-nutrition-prod.ts
 */

const TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
const REF = process.env.SUPABASE_PROJECT_REF ?? 'nkugeupizmphbeicykpj';
if (!TOKEN) throw new Error('SUPABASE_ACCESS_TOKEN 未设置(从 keychain 注入)');

function lit(s: string): string {
  return `'${s.replace(/'/g, "''")}'`;
}
function jsonbOrNull(v: unknown): string {
  return v == null ? 'null::jsonb' : `${lit(JSON.stringify(v))}::jsonb`;
}

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
const targets = recipes.filter((r) => r.nutrition || r.stepDurations);

const rows = targets
  .map((r) => `(${lit(r.id)}, ${jsonbOrNull(r.nutrition)}, ${jsonbOrNull(r.stepDurations)})`)
  .join(',\n');

const sql = `update public.recipes as r set
  nutrition = v.nutrition,
  step_durations = v.step_durations
from (values
${rows}
) as v(id, nutrition, step_durations)
where r.id = v.id;`;

const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql }),
});
const body = await res.text();
console.log('HTTP', res.status);
console.log('响应', body.slice(0, 400));
console.log(`目标 ${targets.length} 条(营养 ${targets.filter((r) => r.nutrition).length} / 时长 ${targets.filter((r) => r.stepDurations).length})`);
