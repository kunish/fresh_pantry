# recipe-pipeline:Kimi 模型替换 + 菜谱视频搜集补齐 + 全量重跑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 recipe-pipeline 的 LLM enrich 换成 Cloudflare Workers AI 的 `@cf/moonshotai/kimi-k2.7-code`,为 364 道菜新增可外链播放的视频字段(搜集+补齐),并用新模型全量重跑一遍。

**Architecture:** 模型替换走「直连 enricher 藏在现有 `RecipeEnricher` seam 后」——新 `CloudflareEnricher` 直接 fetch CF OpenAI 兼容 `/chat/completions`,`response_format: json_schema` + 容量错指数退避重试,可全单测;视频走「外链 URL」,镜像既有「联网补图」的 `applyAcquiredImages`/attribution/workflow 三件套,iOS 端 `SFSafariViewController` 打开。数据流:howtocook.json → Supabase `recipes` 表 → iOS。

**Tech Stack:** TypeScript(Flue runtime / vitest / valibot / `@valibot/to-json-schema`)、Swift(SwiftUI / SafariServices)、Supabase(Postgres 迁移)、ultracode Workflow(视频搜集 fan-out)。

参考 spec:`docs/superpowers/specs/2026-06-13-recipe-pipeline-kimi-and-video-design.md`

---

## 文件结构

**新建**
- `apps/recipe-pipeline/src/clean/cloudflare-enricher.ts` — CF 直连 enricher(重试/json_schema/解析)。
- `apps/recipe-pipeline/test/cloudflare-enricher.test.ts` — 上者单测(注入 fetch/sleep)。
- `apps/recipe-pipeline/src/clean/fetch-videos.ts` — `applyAcquiredVideos`/`mergeVideoAttributions` 纯函数。
- `apps/recipe-pipeline/test/fetch-videos.test.ts` — 上者单测。
- `apps/recipe-pipeline/src/db/apply-web-videos.ts` — 聚合 workflow 产物回写 howtocook.json + 出处(`videos:apply`)。
- `apps/recipe-pipeline/data/acquired-videos/acquire-videos.workflow.mjs` — 每菜一 agent 搜视频外链(ultracode)。
- `apps/ios/FreshPantry/Features/Recipes/SafariView.swift` — `SFSafariViewController` 的 SwiftUI 包装。

**修改**
- `apps/recipe-pipeline/package.json` — 加 `@valibot/to-json-schema` 依赖 + `videos:apply` 脚本。
- `apps/recipe-pipeline/src/config.ts` — CF 凭据 + `useCloudflare` 判据 + 默认模型 + `videoAttributionsPath`。
- `apps/recipe-pipeline/src/workflows/build-recipes.ts` — 按 config 选 enricher。
- `apps/recipe-pipeline/src/clean/schema.ts` — `CleanRecipeSchema` 加 `videoUrl`。
- `apps/recipe-pipeline/src/clean/enrich.ts` — `assembleRecipe` 输出 `videoUrl: null`。
- `apps/recipe-pipeline/src/clean/merge.ts` — `videoUrl` 既有优先。
- `apps/recipe-pipeline/src/db/recipe-sql.ts` — `video_url` 列(DDL/COLUMNS/valuesRow/CatalogRecipe)。
- `apps/recipe-pipeline/.env.example` + `README.md` — CF 渠道 + 视频用法。
- `apps/ios/FreshPantry/Domain/Models/Recipe.swift` — `videoUrl` 字段 + Codable。
- `apps/ios/FreshPantry/Persistence/Repositories/RemoteRecipeCatalog.swift` — select 列别名加 `videoUrl:video_url`。
- `apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift` — 「观看视频」入口 + sheet。
- `apps/ios/FreshPantryTests/EntityRoundTripTests.swift` — `videoUrl` 往返/缺字段测试。
- `apps/recipe-pipeline/test/recipe-sql.test.ts` / `test/merge.test.ts` / `test/schema.test.ts` — 扩 `videoUrl`。

---

## Phase 1:模型替换(CloudflareEnricher)

### Task 1: 加 `@valibot/to-json-schema` 依赖

**Files:**
- Modify: `apps/recipe-pipeline/package.json`

- [ ] **Step 1: 装依赖**

Run(在 `apps/recipe-pipeline/`):
```bash
npm install @valibot/to-json-schema@^1.3.0
```
Expected: `package.json` 的 `dependencies` 新增 `"@valibot/to-json-schema": "^1.3.0"`,`package-lock.json` 更新,无报错。

- [ ] **Step 2: 验证可导入**

Run:
```bash
node --input-type=module -e "import('@valibot/to-json-schema').then(m=>console.log(typeof m.toJsonSchema))"
```
Expected: 打印 `function`。

- [ ] **Step 3: Commit**

```bash
git add apps/recipe-pipeline/package.json apps/recipe-pipeline/package-lock.json
git commit -m "build(recipe-pipeline): 加 @valibot/to-json-schema 依赖"
```

---

### Task 2: `CloudflareEnricher`(TDD)

**Files:**
- Create: `apps/recipe-pipeline/src/clean/cloudflare-enricher.ts`
- Test: `apps/recipe-pipeline/test/cloudflare-enricher.test.ts`

- [ ] **Step 1: 写失败测试**

Create `apps/recipe-pipeline/test/cloudflare-enricher.test.ts`:
```ts
import { describe, it, expect, vi } from 'vitest';
import { createCloudflareEnricher, extractJson } from '../src/clean/cloudflare-enricher';
import type { RawRecipe } from '../src/sources/types';

const raw: RawRecipe = {
  id: 'howtocook:vegetable_dish/番茄炒蛋',
  name: '番茄炒蛋',
  sourceRef: 'x',
  rawIngredients: ['番茄', '鸡蛋'],
  steps: ['切番茄', '打蛋', '炒'],
} as RawRecipe;

const validEnrichment = {
  category: '荤菜',
  difficulty: 1,
  cookingMinutes: 10,
  description: '经典家常菜。',
  ingredients: [{ name: '番茄', quantity: 2, unit: '个' }, { name: '鸡蛋', quantity: 3, unit: '个' }],
  steps: ['切番茄', '打蛋', '炒'],
  tags: ['快手'],
};

function okResponse(content: string) {
  return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content } }] }) };
}
function capacityResponse() {
  return { ok: false, status: 200, json: async () => ({ errors: [{ code: 3040, message: 'AiError: Capacity temporarily exceeded' }] }) };
}

describe('extractJson', () => {
  it('剥掉 ```json fences 与前置思考文本', () => {
    expect(JSON.parse(extractJson('思考...\n```json\n{"a":1}\n```'))).toEqual({ a: 1 });
    expect(JSON.parse(extractJson('{"a":1}'))).toEqual({ a: 1 });
  });
});

describe('createCloudflareEnricher', () => {
  it('容量错(code 3040)先重试、后成功', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(capacityResponse())
      .mockResolvedValueOnce(okResponse(JSON.stringify(validEnrichment)));
    const sleep = vi.fn().mockResolvedValue(undefined);
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: '@cf/moonshotai/kimi-k2.7-code',
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep,
    });
    const out = await enricher.enrich(raw);
    expect(out.category).toBe('荤菜');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(sleep).toHaveBeenCalledTimes(1); // 重试前退避一次
  });

  it('429 也重试', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce({ ok: false, status: 429, json: async () => ({ error: { message: 'rate limited' } }) })
      .mockResolvedValueOnce(okResponse(JSON.stringify(validEnrichment)));
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: 'm',
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep: async () => {},
    });
    await expect(enricher.enrich(raw)).resolves.toMatchObject({ difficulty: 1 });
  });

  it('不可重试错误(400)直接抛', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: false, status: 400, json: async () => ({ error: { message: 'bad request' } }) });
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: 'm', maxRetries: 2,
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep: async () => {},
    });
    await expect(enricher.enrich(raw)).rejects.toThrow(/bad request/);
    expect(fetchImpl).toHaveBeenCalledTimes(1); // 400 不重试
  });

  it('首响坏 JSON → 重提一次后成功', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(okResponse('这不是 JSON'))
      .mockResolvedValueOnce(okResponse(JSON.stringify(validEnrichment)));
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: 'm',
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep: async () => {},
    });
    await expect(enricher.enrich(raw)).resolves.toMatchObject({ category: '荤菜' });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/cloudflare-enricher.test.ts`
Expected: FAIL —「Cannot find module '../src/clean/cloudflare-enricher'」。

- [ ] **Step 3: 实现**

Create `apps/recipe-pipeline/src/clean/cloudflare-enricher.ts`:
```ts
import * as v from 'valibot';
import { toJsonSchema } from '@valibot/to-json-schema';
import { EnrichmentSchema, type Enrichment } from './schema';
import { buildEnrichPrompt, RECIPE_CLEANER_INSTRUCTIONS, type RecipeEnricher } from './enrich';
import type { RawRecipe } from '../sources/types';

export interface CloudflareEnricherOptions {
  baseUrl: string;            // …/accounts/<id>/ai/v1
  apiKey: string;
  model: string;              // @cf/moonshotai/kimi-k2.7-code
  maxTokens?: number;         // 默认 4096(推理模型烧 token,给足)
  maxRetries?: number;        // 默认 5
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  log?: (msg: string) => void;
}

/** EnrichmentSchema → JSON Schema(模块加载时算一次)。strict 留给 v.parse 兜底。 */
export const ENRICHMENT_JSON_SCHEMA = toJsonSchema(EnrichmentSchema, { errorMode: 'ignore' });

/** 推理模型可能包 ```json fences 或前置思考文本;抽出第一个 {...} 块。 */
export function extractJson(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf('{');
  const end = candidate.lastIndexOf('}');
  return start >= 0 && end > start ? candidate.slice(start, end + 1) : candidate.trim();
}

interface Classified { ok: boolean; content?: string; retryable: boolean; message: string; }

/** 判定一次响应:成功取 content;失败识别容量/限流/5xx 为可重试。 */
function classify(status: number, body: unknown): Classified {
  const b = body as { choices?: { message?: { content?: unknown } }[]; errors?: { code?: number; message?: string }[]; error?: { message?: string } };
  const content = b?.choices?.[0]?.message?.content;
  if (typeof content === 'string' && content.length > 0) {
    return { ok: true, content, retryable: false, message: '' };
  }
  const errs = b?.errors ?? (b?.error ? [b.error] : []);
  const message = errs.map((e) => e?.message ?? '').filter(Boolean).join('; ') || `HTTP ${status}`;
  const code = (errs[0] as { code?: number })?.code;
  const capacity = code === 3040 || /capacity/i.test(message);
  const retryable = capacity || status === 429 || status >= 500;
  return { ok: false, retryable, message };
}

export function createCloudflareEnricher(opts: CloudflareEnricherOptions): RecipeEnricher {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const maxTokens = opts.maxTokens ?? 4096;
  const maxRetries = opts.maxRetries ?? 5;
  const log = opts.log ?? (() => {});

  async function backoff(attempt: number): Promise<void> {
    const base = Math.min(30_000, 1_000 * 2 ** attempt);
    await sleep(base + base * 0.25 * Math.random()); // 抖动避免雪崩
  }

  async function call(messages: { role: string; content: string }[]): Promise<string> {
    let lastMsg = '';
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      let status = 0;
      let body: unknown;
      try {
        const res = await fetchImpl(`${opts.baseUrl}/chat/completions`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${opts.apiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            model: opts.model,
            messages,
            response_format: { type: 'json_schema', json_schema: { name: 'enrichment', schema: ENRICHMENT_JSON_SCHEMA } },
            max_tokens: maxTokens,
          }),
        });
        status = res.status;
        body = await res.json();
      } catch (e) {
        lastMsg = e instanceof Error ? e.message : String(e);
        if (attempt < maxRetries) { log(`网络错重试 ${attempt + 1}/${maxRetries}: ${lastMsg}`); await backoff(attempt); continue; }
        throw new Error(`Cloudflare 请求失败(网络): ${lastMsg}`);
      }
      const c = classify(status, body);
      if (c.ok) return c.content!;
      lastMsg = c.message;
      if (c.retryable && attempt < maxRetries) { log(`重试 ${attempt + 1}/${maxRetries}: ${c.message}`); await backoff(attempt); continue; }
      throw new Error(`Cloudflare 返回错误: ${c.message}`);
    }
    throw new Error(`Cloudflare 重试耗尽: ${lastMsg}`);
  }

  async function parseOrThrow(content: string): Promise<Enrichment> {
    return v.parse(EnrichmentSchema, JSON.parse(extractJson(content)));
  }

  return {
    async enrich(raw: RawRecipe): Promise<Enrichment> {
      const messages = [
        { role: 'system', content: RECIPE_CLEANER_INSTRUCTIONS },
        { role: 'user', content: buildEnrichPrompt(raw) },
      ];
      const first = await call(messages);
      try {
        return await parseOrThrow(first);
      } catch {
        const retried = await call([
          ...messages,
          { role: 'assistant', content: first },
          { role: 'user', content: '只返回符合要求的 JSON 对象,不要任何解释或 markdown 代码块。' },
        ]);
        return await parseOrThrow(retried);
      }
    },
  };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/cloudflare-enricher.test.ts`
Expected: PASS,5 个用例全绿。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/clean/cloudflare-enricher.ts apps/recipe-pipeline/test/cloudflare-enricher.test.ts
git commit -m "feat(recipe-pipeline): CloudflareEnricher 直连 Kimi(json_schema + 容量退避重试)"
```

---

### Task 3: 接线 config + build-recipes 选择 enricher

**Files:**
- Modify: `apps/recipe-pipeline/src/config.ts`
- Modify: `apps/recipe-pipeline/src/workflows/build-recipes.ts`
- Modify: `apps/recipe-pipeline/.env.example`

- [ ] **Step 1: 改 config**

在 `apps/recipe-pipeline/src/config.ts` 的 `config` 对象里:把 `model` 默认改成 Kimi,新增 `useCloudflare`/`cloudflare`/`videoAttributionsPath`。整体替换 `export const config = {…}`:
```ts
const CF_DEFAULT_BASE =
  'https://api.cloudflare.com/client/v4/accounts/3967805080c0f0812c8e59d1f9c699a6/ai/v1';
const recipeModel = process.env.RECIPE_MODEL ?? '@cf/moonshotai/kimi-k2.7-code';

export const config = {
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  imagesDir: resolve(root, '../ios/FreshPantry/Resources/RecipeImages'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  sourcesPath: resolve(root, 'data/sources.json'),
  attributionsPath: resolve(root, 'data/image-attributions.json'),
  videoAttributionsPath: resolve(root, 'data/video-attributions.json'),
  workDir: resolve(root, '.cache'),
  acquireImages: process.env.RECIPE_ACQUIRE_IMAGES === '1',
  model: recipeModel,
  // RECIPE_MODEL 以 @cf/ 开头 → 走 CloudflareEnricher(直连 OpenAI 兼容端点),否则走 flue。
  useCloudflare: recipeModel.startsWith('@cf/'),
  cloudflare: {
    baseUrl: process.env.CLOUDFLARE_AI_BASE_URL ?? CF_DEFAULT_BASE,
    apiKey: process.env.CLOUDFLARE_AI_API_KEY ?? '',
    maxTokens: Number(process.env.RECIPE_MAX_TOKENS ?? '4096'),
  },
  thinkingLevel: (process.env.RECIPE_THINKING ?? 'xhigh') as 'off' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};
```

- [ ] **Step 2: 改 build-recipes 选 enricher**

替换 `apps/recipe-pipeline/src/workflows/build-recipes.ts` 顶部 import 与 `run` 内 enricher 构造:
```ts
import { readFile } from 'node:fs/promises';
import type { FlueContext } from '@flue/runtime';
import recipeCleaner from '../agents/recipe-cleaner';
import { createFlueEnricher } from '../clean/flue-enricher';
import { createCloudflareEnricher } from '../clean/cloudflare-enricher';
import { buildSources, type SourcesFile } from '../sources/registry';
import { createOpenverseSearch } from '../sources/image-search-openverse';
import { runPipeline } from '../pipeline';
import { config } from '../config';
```
然后把 `run` 函数体开头两行:
```ts
  const harness = await init(recipeCleaner);
  const enricher = createFlueEnricher(harness);
```
替换为(只在走 flue 路径时才 `await init(recipeCleaner)`,CF 路径不需要 harness):
```ts
  const enricher = config.useCloudflare
    ? createCloudflareEnricher({
        baseUrl: config.cloudflare.baseUrl,
        apiKey: config.cloudflare.apiKey,
        model: config.model,
        maxTokens: config.cloudflare.maxTokens,
        log: (m) => console.log(`[recipes:cf] ${m}`),
      })
    : createFlueEnricher(await init(recipeCleaner));
```

- [ ] **Step 3: 改 .env.example**

整体替换 `apps/recipe-pipeline/.env.example`:
```
# 默认:Cloudflare Workers AI 渠道(OpenAI 兼容),模型 @cf/moonshotai/kimi-k2.7-code
CLOUDFLARE_AI_API_KEY="cfut_xxx"                # Workers AI 用户 token(Bearer)
# CLOUDFLARE_AI_BASE_URL=".../accounts/<id>/ai/v1"   # 覆盖默认账户 base
# RECIPE_MAX_TOKENS="4096"                       # 推理模型烧 token,给足
# RECIPE_MODEL="@cf/moonshotai/kimi-k2.7-code"  # 以 @cf/ 开头即走 CF 直连

# 备选:Anthropic 直连 / opencode zen(RECIPE_MODEL 不以 @cf/ 开头时启用 flue 路径)
# ANTHROPIC_API_KEY="your-api-key"
# OPENCODE_API_KEY="your-opencode-key"
# RECIPE_MODEL="opencode-go/deepseek-v4-pro"
# RECIPE_THINKING="xhigh"
```

- [ ] **Step 4: typecheck + 全量测试**

Run: `npm run typecheck && npx vitest run`
Expected: typecheck 0 error;现有全部测试 + 新 cloudflare-enricher 测试全绿。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/config.ts apps/recipe-pipeline/src/workflows/build-recipes.ts apps/recipe-pipeline/.env.example
git commit -m "feat(recipe-pipeline): RECIPE_MODEL @cf/ 前缀切 CloudflareEnricher,默认 Kimi"
```

---

### Task 4: 【检查点】Kimi 小样质量验证(人工)

**Files:** 无(操作 + 人工审阅)

- [ ] **Step 1: 准备 .env**

确保 `apps/recipe-pipeline/.env` 有 `CLOUDFLARE_AI_API_KEY=cfut_…`(用户提供的 key)。

- [ ] **Step 2: 跑 5 条 dry-run**

Run:
```bash
npx flue run build-recipes --target node --payload '{"limit":5,"dryRun":true,"skipImages":true}'
```
Expected: 输出 `[recipes] report { collected:5, cleaned:5, rejected:0, … }`(允许个别 reject)。`dryRun` 不写盘。

- [ ] **Step 3: 人工审阅产出质量**

把这 5 条的 enrich 结果(category/difficulty/steps/ingredients 用量结构)交给用户肉眼核对:分类合理、用量「只抽不猜」、无公式系数误当用量、描述通顺。**这是模型替换的质量门——用户确认 OK 才进全量重清洗(Task 13)。** 若 Kimi 质量不达标,提示用户可改 `RECIPE_MODEL=@cf/moonshotai/kimi-k2.6`(通用版)再试 Step 2。

---

## Phase 2:视频数据管线 + DB + iOS

### Task 5: schema `videoUrl` + assemble + merge(TDD)

**Files:**
- Modify: `apps/recipe-pipeline/src/clean/schema.ts:35`
- Modify: `apps/recipe-pipeline/src/clean/enrich.ts:81`
- Modify: `apps/recipe-pipeline/src/clean/merge.ts:41`
- Test: `apps/recipe-pipeline/test/merge.test.ts`

- [ ] **Step 1: 写失败测试**

在 `apps/recipe-pipeline/test/merge.test.ts` 末尾(最后一个 `});` 之前的合适位置,新增 describe;若文件用单一 describe 包裹,加一个 `it`。追加:
```ts
import { describe, it, expect } from 'vitest';
import { mergeWithExisting } from '../src/clean/merge';
import type { CleanRecipe } from '../src/clean/schema';

const base = (over: Partial<CleanRecipe> = {}): CleanRecipe => ({
  id: 'r1', name: '番茄炒蛋', category: '荤菜', difficulty: 1, cookingMinutes: 10,
  description: 'd', ingredients: [], steps: [], tags: [], imageUrl: null,
  videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
});

describe('mergeWithExisting videoUrl', () => {
  it('既有 videoUrl 优先,不被 fresh 的 null 覆盖', () => {
    const fresh = [base({ videoUrl: null })];
    const existing = [base({ videoUrl: 'https://b23.tv/x' })];
    const { merged } = mergeWithExisting(fresh, existing, '2026-06-13T00:00:00Z');
    expect(merged[0].videoUrl).toBe('https://b23.tv/x');
  });
  it('既有无 videoUrl 时采纳 fresh 的', () => {
    const fresh = [base({ videoUrl: 'https://youtu.be/y' })];
    const existing = [base({ videoUrl: null })];
    const { merged } = mergeWithExisting(fresh, existing, '2026-06-13T00:00:00Z');
    expect(merged[0].videoUrl).toBe('https://youtu.be/y');
  });
});
```
> 若 `merge.test.ts` 已 import 了 `describe/it/expect`/`mergeWithExisting`,删掉本段重复 import,只保留新 describe。

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/merge.test.ts`
Expected: FAIL —`base()` 里的 `videoUrl` 不在 `CleanRecipe` 类型上(TS 报错)/ `merged[0].videoUrl` 为 undefined。

- [ ] **Step 3: 实现 schema**

`apps/recipe-pipeline/src/clean/schema.ts`:在 `CleanRecipeSchema` 的 `imageUrl: v.nullable(v.string()),`(第 35 行)下一行加:
```ts
  videoUrl: v.nullable(v.string()),
```
(放在 `imageUrl` 与 `remoteVersion` 之间。`EnrichmentSchema` 不动——视频不由 LLM 产出。)

- [ ] **Step 4: 实现 assemble**

`apps/recipe-pipeline/src/clean/enrich.ts`:在 `assembleRecipe` 返回对象里 `imageUrl: raw.imageUrl ?? null,`(第 81 行)下一行加:
```ts
    videoUrl: null,
```

- [ ] **Step 5: 实现 merge 保护**

`apps/recipe-pipeline/src/clean/merge.ts`:在 `mergeWithExisting` 的 update 分支 `byId.set(f.id, { … })` 里 `imageUrl: prev.imageUrl || f.imageUrl,`(第 41 行)下一行加:
```ts
      videoUrl: prev.videoUrl || f.videoUrl,
```

- [ ] **Step 6: 跑测试 + typecheck 确认通过**

Run: `npx vitest run test/merge.test.ts && npm run typecheck`
Expected: PASS;typecheck 0 error。

- [ ] **Step 7: Commit**

```bash
git add apps/recipe-pipeline/src/clean/schema.ts apps/recipe-pipeline/src/clean/enrich.ts apps/recipe-pipeline/src/clean/merge.ts apps/recipe-pipeline/test/merge.test.ts
git commit -m "feat(recipe-pipeline): CleanRecipe 加 videoUrl(assemble null + merge 既有优先)"
```

---

### Task 6: DB `video_url` 列(TDD)

**Files:**
- Modify: `apps/recipe-pipeline/src/db/recipe-sql.ts`
- Test: `apps/recipe-pipeline/test/recipe-sql.test.ts`

- [ ] **Step 1: 写失败测试**

在 `apps/recipe-pipeline/test/recipe-sql.test.ts` 的 `recipe()` 工厂里给默认值加 `videoUrl`(在 `imageUrl:` 行下面):
```ts
  videoUrl: null,
```
并在 `describe('recipesToSeedSQL', …)` 内新增用例:
```ts
  it('video_url 入列:DDL 含 alter 升级,空 → null,有值 → 字面量', () => {
    expect(RECIPES_DDL).toContain('video_url text');
    expect(RECIPES_DDL).toContain('add column if not exists video_url text');
    expect(recipesToUpsertSQL([recipe({ videoUrl: null })])).toContain(', null)');
    expect(recipesToUpsertSQL([recipe({ videoUrl: 'https://b23.tv/x' })])).toContain("'https://b23.tv/x'");
    expect(recipesToUpsertSQL([recipe()])).toContain('video_url');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/recipe-sql.test.ts`
Expected: FAIL — `CatalogRecipe` 无 `videoUrl` 字段(TS 报错)/ DDL 不含 `video_url`。

- [ ] **Step 3: 实现**

`apps/recipe-pipeline/src/db/recipe-sql.ts`,四处改:

(a) `CatalogRecipe` 的 Pick 加 `'videoUrl'`:
```ts
export type CatalogRecipe = Pick<
  CleanRecipe,
  'id' | 'name' | 'category' | 'difficulty' | 'cookingMinutes' | 'description'
  | 'ingredients' | 'steps' | 'tags' | 'imageUrl' | 'videoUrl'
>;
```

(b) `COLUMNS` 在 `'image_url'` 后加 `'video_url'`:
```ts
const COLUMNS = [
  'id', 'name', 'category', 'difficulty', 'cooking_minutes',
  'description', 'ingredients', 'steps', 'tags', 'image_url', 'video_url',
] as const;
```

(c) `RECIPES_DDL`:create table 里 `image_url text,` 下加 `video_url text,`;并在 `grant select …` 后追加幂等升级语句。整体替换 `RECIPES_DDL`:
```ts
export const RECIPES_DDL = `create table if not exists public.recipes (
  id text primary key,
  name text not null,
  category text not null default '',
  difficulty integer not null default 0,
  cooking_minutes integer not null default 30,
  description text not null default '',
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  tags jsonb not null default '[]'::jsonb,
  image_url text,
  video_url text,
  updated_at timestamptz not null default now()
);

-- 老库幂等升级:新增 video_url 列(已存在则无操作)
alter table public.recipes add column if not exists video_url text;

alter table public.recipes enable row level security;
-- 共享菜谱目录:匿名 + 已登录均可只读;无写策略(仅 service_role/迁移可写)
drop policy if exists "recipes_public_read" on public.recipes;
create policy "recipes_public_read" on public.recipes
  for select to anon, authenticated using (true);
grant select on public.recipes to anon, authenticated;`;
```

(d) `valuesRow` 末尾加 `video_url`:
```ts
function valuesRow(r: CatalogRecipe): string {
  return `  (${lit(r.id)}, ${lit(r.name)}, ${lit(r.category)}, ${r.difficulty}, `
    + `${r.cookingMinutes}, ${lit(r.description)}, ${jsonbLit(r.ingredients)}, `
    + `${jsonbLit(r.steps)}, ${jsonbLit(r.tags)}, ${nullableText(r.imageUrl)}, `
    + `${nullableText(r.videoUrl)})`;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/recipe-sql.test.ts`
Expected: PASS。注意原有用例「多条 → 多行 VALUES」断言 `::jsonb` 出现 6 次仍成立(video_url 是 text 非 jsonb,不影响)。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/db/recipe-sql.ts apps/recipe-pipeline/test/recipe-sql.test.ts
git commit -m "feat(recipe-pipeline): recipes 表加 video_url 列(DDL 幂等升级 + 种子)"
```

---

### Task 7: `applyAcquiredVideos` / `mergeVideoAttributions`(TDD)

**Files:**
- Create: `apps/recipe-pipeline/src/clean/fetch-videos.ts`
- Test: `apps/recipe-pipeline/test/fetch-videos.test.ts`

- [ ] **Step 1: 写失败测试**

Create `apps/recipe-pipeline/test/fetch-videos.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { applyAcquiredVideos, mergeVideoAttributions, type VideoAttribution } from '../src/clean/fetch-videos';
import type { CleanRecipe } from '../src/clean/schema';

const r = (over: Partial<CleanRecipe> = {}): CleanRecipe => ({
  id: 'r1', name: '番茄炒蛋', category: '荤菜', difficulty: 1, cookingMinutes: 10,
  description: 'd', ingredients: [], steps: [], tags: [], imageUrl: null,
  videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
});

describe('applyAcquiredVideos', () => {
  it('给缺视频的菜回填 videoUrl + 产出出处', () => {
    const recipes = [r({ id: 'a' }), r({ id: 'b' })];
    const { updated, attributions } = applyAcquiredVideos(
      recipes,
      [{ id: 'a', videoUrl: 'https://b23.tv/a', provider: 'bilibili', title: 'A 做法' }],
      '2026-06-13T00:00:00Z',
    );
    expect(updated).toBe(1);
    expect(recipes[0].videoUrl).toBe('https://b23.tv/a');
    expect(recipes[1].videoUrl).toBeNull();
    expect(attributions[0]).toMatchObject({ id: 'a', videoUrl: 'https://b23.tv/a', provider: 'bilibili' });
  });
  it('既有 videoUrl 不覆盖;空 videoUrl 的 acquired 跳过;软删跳过', () => {
    const recipes = [r({ id: 'a', videoUrl: 'https://old' }), r({ id: 'c', deletedAt: '2026-01-01T00:00:00Z' })];
    const { updated } = applyAcquiredVideos(
      recipes,
      [{ id: 'a', videoUrl: 'https://new' }, { id: 'c', videoUrl: 'https://x' }, { id: 'd', videoUrl: '' }],
      '2026-06-13T00:00:00Z',
    );
    expect(updated).toBe(0);
    expect(recipes[0].videoUrl).toBe('https://old');
  });
});

describe('mergeVideoAttributions', () => {
  it('按 id 合并(新覆盖旧)并按 id 排序', () => {
    const prev: VideoAttribution[] = [{ id: 'b', name: 'B', videoUrl: 'u_b_old', acquiredAt: 't' }];
    const next: VideoAttribution[] = [
      { id: 'a', name: 'A', videoUrl: 'u_a', acquiredAt: 't' },
      { id: 'b', name: 'B', videoUrl: 'u_b_new', acquiredAt: 't' },
    ];
    const merged = mergeVideoAttributions(prev, next);
    expect(merged.map((m) => m.id)).toEqual(['a', 'b']);
    expect(merged.find((m) => m.id === 'b')!.videoUrl).toBe('u_b_new');
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/fetch-videos.test.ts`
Expected: FAIL —「Cannot find module '../src/clean/fetch-videos'」。

- [ ] **Step 3: 实现**

Create `apps/recipe-pipeline/src/clean/fetch-videos.ts`:
```ts
import type { CleanRecipe } from './schema';

/**
 * 菜谱视频:外链 URL。镜像 `fetch-images.ts` 的 applyAcquiredImages/mergeAttributions——
 * ultracode「联网搜视频」workflow 每菜产出一条 {id, videoUrl, …},本模块纯函数把
 * videoUrl 回写进仍缺视频的菜谱(既有优先),并产出可溯源出处。视频不下载、不托管,只存外链。
 */

/** workflow agent 回传的一条视频结果(视频是外链,无文件落盘)。 */
export interface AcquiredVideo {
  id: string;
  videoUrl: string;
  sourcePage?: string;
  title?: string;
  provider?: string; // bilibili / youtube / xiachufang / …
}

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

/**
 * 纯函数:把搜到的外链回写进仍缺视频的菜谱 videoUrl(既有优先,软删跳过),并产出出处。
 */
export function applyAcquiredVideos(
  recipes: CleanRecipe[],
  acquired: AcquiredVideo[],
  now: string,
): { updated: number; attributions: VideoAttribution[] } {
  const byId = new Map(acquired.map((a) => [a.id, a]));
  let updated = 0;
  const attributions: VideoAttribution[] = [];
  for (const r of recipes) {
    const a = byId.get(r.id);
    if (!a || !a.videoUrl) continue;
    if (!needsVideo(r)) continue; // 既有优先
    r.videoUrl = a.videoUrl;
    updated++;
    attributions.push({
      id: r.id, name: r.name, videoUrl: a.videoUrl,
      sourcePage: a.sourcePage, title: a.title, provider: a.provider, acquiredAt: now,
    });
  }
  return { updated, attributions };
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/fetch-videos.test.ts`
Expected: PASS,4 个用例全绿。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/clean/fetch-videos.ts apps/recipe-pipeline/test/fetch-videos.test.ts
git commit -m "feat(recipe-pipeline): applyAcquiredVideos/mergeVideoAttributions 纯函数(外链回写)"
```

---

### Task 8: `apply-web-videos.ts` 回写脚本 + `videos:apply`

**Files:**
- Create: `apps/recipe-pipeline/src/db/apply-web-videos.ts`
- Modify: `apps/recipe-pipeline/package.json`

- [ ] **Step 1: 实现脚本**

Create `apps/recipe-pipeline/src/db/apply-web-videos.ts`:
```ts
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  applyAcquiredVideos, mergeVideoAttributions,
  type AcquiredVideo, type VideoAttribution,
} from '../clean/fetch-videos';
import type { CleanRecipe } from '../clean/schema';
import { config } from '../config';

/**
 * 把 ultracode「联网搜视频」workflow 的产物回写进 howtocook.json。
 * 用 tsx 直跑:`npx tsx src/db/apply-web-videos.ts`(= `npm run videos:apply`)。
 *
 * 每个 agent 把这一条结果写成 data/acquired-videos/<index>.json。本脚本聚合,
 * 经已测纯函数 applyAcquiredVideos 给仍缺视频的菜谱回填 videoUrl(外链,既有优先),
 * 并把出处合并进 data/video-attributions.json。重跑后 `npm run gen:seed` 同步 DB。
 */
const here = dirname(fileURLToPath(import.meta.url));
const acquiredDir = resolve(here, '../../data/acquired-videos');

interface MetaFile {
  index?: number;
  id?: string;
  ok?: boolean;
  videoUrl?: string | null;
  sourcePage?: string | null;
  title?: string | null;
  provider?: string | null;
  confidence?: string | null;
  reason?: string;
}

function readMetaFiles(): MetaFile[] {
  const metas: MetaFile[] = [];
  if (!existsSync(acquiredDir)) return metas;
  for (const name of readdirSync(acquiredDir)) {
    if (!/^\d+\.json$/.test(name)) continue; // 只收 <index>.json,跳过 _dishes.json
    try {
      metas.push(JSON.parse(readFileSync(join(acquiredDir, name), 'utf8')) as MetaFile);
    } catch {
      console.warn(`跳过损坏的 meta: ${name}`);
    }
  }
  return metas;
}

const metas = readMetaFiles();
// 只采纳 ok 且有真实 http(s) videoUrl 的(防 agent 自报 ok 但 url 空/无效)。
const acquired: AcquiredVideo[] = metas
  .filter((m) => m.ok && m.id && m.videoUrl && /^https?:\/\//.test(m.videoUrl))
  .map((m) => ({
    id: m.id!, videoUrl: m.videoUrl!,
    sourcePage: m.sourcePage ?? undefined, title: m.title ?? undefined,
    provider: m.provider ?? undefined,
  }));

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
const now = new Date().toISOString();
const { updated, attributions } = applyAcquiredVideos(recipes, acquired, now);

writeFileSync(config.outPath, JSON.stringify(recipes, null, 2) + '\n', 'utf8');

const prevAttr: VideoAttribution[] = existsSync(config.videoAttributionsPath)
  ? (JSON.parse(readFileSync(config.videoAttributionsPath, 'utf8')) as VideoAttribution[])
  : [];
const mergedAttr = mergeVideoAttributions(prevAttr, attributions);
writeFileSync(config.videoAttributionsPath, JSON.stringify(mergedAttr, null, 2) + '\n', 'utf8');

const stillMissing = recipes.filter((r) => (r.videoUrl === null || r.videoUrl === '') && !r.deletedAt).length;
console.log(`apply-web-videos:`);
console.log(`  meta 文件 ${metas.length} 条,有效外链 ${acquired.length} 条`);
console.log(`  回写 videoUrl ${updated} 条 → ${config.outPath}`);
console.log(`  出处累计 ${mergedAttr.length} 条 → ${config.videoAttributionsPath}`);
console.log(`  仍缺视频 ${stillMissing} 条`);
```

- [ ] **Step 2: 加 npm 脚本**

`apps/recipe-pipeline/package.json` 的 `scripts` 里,在 `"images:apply"` 行后加:
```json
    "videos:apply": "npx tsx src/db/apply-web-videos.ts",
```

- [ ] **Step 3: typecheck + 冒烟(空目录安全)**

Run: `npm run typecheck && npx tsx src/db/apply-web-videos.ts`
Expected: typecheck 0 error;脚本在 `data/acquired-videos/` 不存在时打印「meta 文件 0 条 … 回写 0 条」,**不改变 howtocook.json 的 videoUrl(全保持 null)**,不报错。
> ⚠️ 此步会把 howtocook.json 重写一遍(加上 `videoUrl: null` 字段,因为 schema 已含)。跑后 `git diff --stat` 确认只是新增 videoUrl 字段。**先不要 commit 这个大 diff**——它会在 Task 13 全量重清洗时一并产生。本步只验证脚本不崩;验证后 `git checkout -- ../ios/FreshPantry/Resources/howtocook.json` 还原。

- [ ] **Step 4: 还原 + Commit(只提交脚本与 package.json)**

```bash
git checkout -- apps/ios/FreshPantry/Resources/howtocook.json
git add apps/recipe-pipeline/src/db/apply-web-videos.ts apps/recipe-pipeline/package.json
git commit -m "feat(recipe-pipeline): videos:apply 聚合 workflow 产物回写外链 + 出处"
```

---

### Task 9: iOS `Recipe.videoUrl`(TDD)

**Files:**
- Modify: `apps/ios/FreshPantry/Domain/Models/Recipe.swift`
- Test: `apps/ios/FreshPantryTests/EntityRoundTripTests.swift`

- [ ] **Step 1: 写失败测试**

在 `apps/ios/FreshPantryTests/EntityRoundTripTests.swift` 的 `recipeRoundTrip()` 测试后,新增:
```swift
    @Test func recipeVideoUrlRoundTrip() throws {
        let recipe = Recipe(
            id: "r_v", name: "红烧肉", category: "荤菜", difficulty: 3,
            cookingMinutes: 60, description: "下饭",
            ingredients: [], steps: ["焯水", "炖"], tags: [],
            imageUrl: "img", videoUrl: "https://b23.tv/abc"
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded.videoUrl == "https://b23.tv/abc")
    }

    @Test func recipeMissingVideoUrlDecodesNil() throws {
        // 老数据没有 videoUrl 键 → 向后兼容解码为 nil。
        let legacy = #"{"id":"r1","name":"n","category":"荤菜","difficulty":1,"cookingMinutes":10,"description":"d","ingredients":[],"steps":[],"tags":[],"imageUrl":null,"remoteVersion":0,"clientUpdatedAt":null,"deletedAt":null}"#
        let decoded = try DomainJSON.decode(Recipe.self, from: legacy)
        #expect(decoded.videoUrl == nil)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run(在 `apps/ios/`,先 `xcodegen generate`):
```bash
cd apps/ios && xcodegen generate && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FreshPantryTests/EntityRoundTripTests 2>&1 | tail -30
```
Expected: 编译失败 —`Recipe.init` 无 `videoUrl` 形参 / `Recipe` 无 `videoUrl` 成员。

- [ ] **Step 3: 实现**

`apps/ios/FreshPantry/Domain/Models/Recipe.swift`,六处改(镜像 `imageUrl`):

(a) 属性(在 `var imageUrl: String?` 后):
```swift
    var videoUrl: String?
```
(b) `init` 形参(在 `imageUrl: String? = nil,` 后)+ 赋值:
```swift
        videoUrl: String? = nil,
```
```swift
        self.videoUrl = videoUrl
```
(c) `CodingKeys`:把 `case ingredients, steps, tags, imageUrl` 改成:
```swift
        case ingredients, steps, tags, imageUrl, videoUrl
```
(d) `encode`:在 `try c.encodeAlways(imageUrl, forKey: .imageUrl)` 后加:
```swift
        try c.encodeAlways(videoUrl, forKey: .videoUrl)
```
(e) `init(from:)`:在 `imageUrl: c.decodeLenientIfPresent(String.self, forKey: .imageUrl),` 后加:
```swift
            videoUrl: c.decodeLenientIfPresent(String.self, forKey: .videoUrl),
```
(f) `copyWith`:形参(在 `imageUrl: String? = nil,` 后)+ 传参:
```swift
        videoUrl: String? = nil,
```
```swift
            videoUrl: videoUrl ?? self.videoUrl,
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FreshPantryTests/EntityRoundTripTests 2>&1 | tail -20
```
Expected: PASS,含两个新视频用例。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Domain/Models/Recipe.swift apps/ios/FreshPantryTests/EntityRoundTripTests.swift
git commit -m "feat(ios): Recipe 加 videoUrl(encodeAlways + 向后兼容解码)"
```

---

### Task 10: iOS catalog 列别名

**Files:**
- Modify: `apps/ios/FreshPantry/Persistence/Repositories/RemoteRecipeCatalog.swift:39`

- [ ] **Step 1: 实现**

把 `private static let columns =` 那行末尾的 `imageUrl:image_url` 后追加 `,videoUrl:video_url`:
```swift
    private static let columns =
        "id,name,category,difficulty,cookingMinutes:cooking_minutes,description,ingredients,steps,tags,imageUrl:image_url,videoUrl:video_url"
```

- [ ] **Step 2: 编译验证**

Run:
```bash
cd apps/ios && xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: Commit**

```bash
git add apps/ios/FreshPantry/Persistence/Repositories/RemoteRecipeCatalog.swift
git commit -m "feat(ios): RemoteRecipeCatalog select 加 videoUrl:video_url 列别名"
```

---

### Task 11: iOS「观看视频」入口 + SafariView

**Files:**
- Create: `apps/ios/FreshPantry/Features/Recipes/SafariView.swift`
- Modify: `apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift`

- [ ] **Step 1: 建 SafariView**

Create `apps/ios/FreshPantry/Features/Recipes/SafariView.swift`:
```swift
import SwiftUI
import SafariServices

/// 用系统 SFSafariViewController 在应用内打开菜谱视频外链(B站/YouTube/下厨房等)。
/// 视频本身不下载、不托管,仅以外链播放。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
```

- [ ] **Step 2: RecipeDetailView 加状态**

在 `apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift` 的 `@State private var showLeftoverSheet = false` 附近(state 区)加:
```swift
    /// 「观看视频」外链的 in-app Safari 呈现。
    @State private var showVideo = false
```

- [ ] **Step 3: header 加按钮**

在 `header` 计算属性里,描述 `if !recipe.description.trimmed.isEmpty { … }` 块之后(仍在外层 `VStack` 内、`.frame(maxWidth:…)` 之前)加:
```swift
            if let videoUrl = recipe.videoUrl?.trimmed, !videoUrl.isEmpty, URL(string: videoUrl) != nil {
                Button {
                    showVideo = true
                } label: {
                    Label("观看视频", systemImage: "play.rectangle.fill")
                        .font(.fkLabelLarge)
                }
                .buttonStyle(.borderedProminent)
                .tint(.fkPrimary)
                .padding(.top, FkSpacing.xs)
                .accessibilityLabel("观看「\(recipe.name)」的做法视频")
            }
```

- [ ] **Step 4: body 加 sheet**

在 `var body` 的某个 `.sheet(…)` 链里(如 `.sheet(isPresented: $showLeftoverSheet) { … }` 之后)加:
```swift
        .sheet(isPresented: $showVideo) {
            if let videoUrl = recipe.videoUrl?.trimmed, let url = URL(string: videoUrl) {
                SafariView(url: url).ignoresSafeArea()
            }
        }
```

- [ ] **Step 5: 编译 + 测试**

Run:
```bash
cd apps/ios && xcodegen generate && xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 6: Commit**

```bash
git add apps/ios/FreshPantry/Features/Recipes/SafariView.swift apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift
git commit -m "feat(ios): 菜谱详情页加「观看视频」入口(SFSafariViewController 打开外链)"
```

---

## Phase 3:视频搜集 workflow

### Task 12: `acquire-videos.workflow.mjs` + 菜单生成

**Files:**
- Create: `apps/recipe-pipeline/data/acquired-videos/acquire-videos.workflow.mjs`

- [ ] **Step 1: 写 workflow 脚本**

Create `apps/recipe-pipeline/data/acquired-videos/acquire-videos.workflow.mjs`:
```js
export const meta = {
  name: 'acquire-recipe-videos',
  description: '为每道菜联网搜一条「做法视频」外链 + 校验相关性(不下载,只存外链)',
  phases: [
    { title: 'Acquire', detail: '每道菜一个 agent:WebSearch 找视频 → WebFetch 校验是这道菜 → 回外链' },
  ],
};

const A = typeof args === 'string' ? JSON.parse(args) : (args ?? {});
const dishesPath = A.dishesPath;
const acquiredDir = A.acquiredDir;
const all = require(dishesPath); // [{i,id,name,category,ings}]
const indices = A.indices
  ?? (A.start != null
    ? Array.from({ length: A.end - A.start }, (_, i) => i + A.start)
    : Array.from({ length: all.length }, (_, i) => i));
log(`args: ${indices.length} dishes,acquiredDir=${acquiredDir ? 'set' : 'MISSING'}`);

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['index', 'id', 'ok', 'reason'],
  properties: {
    index: { type: 'integer' },
    id: { type: 'string' },
    ok: { type: 'boolean', description: '是否找到一条通过校验的视频外链' },
    videoUrl: { type: ['string', 'null'], description: '视频观看页 URL(http/https),如 B站/YouTube/下厨房' },
    sourcePage: { type: ['string', 'null'], description: '同 videoUrl 或承载页' },
    title: { type: ['string', 'null'], description: '视频标题' },
    provider: { type: ['string', 'null'], enum: ['bilibili', 'youtube', 'xiachufang', 'douguo', 'meishichina', 'other', null] },
    confidence: { type: ['string', 'null'], enum: ['high', 'medium', 'low', null] },
    reason: { type: 'string', description: '一句话:采用了什么视频 / 为何没找到' },
  },
};

function buildPrompt(idx) {
  const d = all[idx];
  const metaPath = `${acquiredDir}/${idx}.json`;
  return `你的任务:为一道中文家常菜从互联网找一条「做法/教程视频」的观看页外链,做相关性校验,然后把结果写成一行 JSON。这是 fresh_pantry app 的菜谱视频补齐。视频不下载、只记外链 URL。

## 这道菜
- id: ${d.id}
- 菜名: ${d.name}
- 分类: ${d.category}
- 主料: ${(d.ings ?? []).join('、') || '(未知)'}
- 目标元数据文件: ${metaPath}

## 第 1 步:搜候选视频
用 WebSearch 搜:「${d.name} 做法 视频」「${d.name} 教程」「${d.name} recipe video」。
优先来源(可信、长期可用):
- 哔哩哔哩 bilibili.com(中文做菜视频最丰富)
- YouTube youtube.com / youtu.be
- 下厨房 xiachufang.com、豆果 douguo.com、美食天下 meishichina.com 的视频页
收集 3~6 个候选视频观看页 URL。

## 第 2 步:校验「确为这道菜的做法视频」
对最相关的 1~3 个候选,用 WebFetch 打开,prompt 让它「提取视频标题、UP主/作者、简介」,据此判断:
- 标题/简介确实是在做「${d.name}」(或其明确别名),不是别的菜、不是 vlog/探店/无关内容;
- 是「做法/教程」类(有烹饪步骤),不是纯吃播;
- 链接是公开可看的观看页(不是登录墙/失效页)。
给 confidence:high(标题直指这道菜的做法)/ medium(很可能是)/ low(不确定,不采用)。

## 第 3 步:写结果
- 找到(confidence high/medium):用 Write 把一行 JSON 写到 ${metaPath}:
  {"index":${idx},"id":"${d.id}","ok":true,"videoUrl":"<观看页URL>","sourcePage":"<同上或承载页>","title":"<视频标题>","provider":"bilibili|youtube|xiachufang|douguo|meishichina|other","confidence":"high|medium","reason":"<简述>"}
- 没找到合适的:**不要硬塞**,Write ${metaPath} 写:
  {"index":${idx},"id":"${d.id}","ok":false,"videoUrl":null,"sourcePage":null,"title":null,"provider":null,"confidence":null,"reason":"<尝试了什么、为何没采用>"}

## 约束
- 绝不修改 howtocook.json 或任何其它已有文件,只新增 ${metaPath}。
- videoUrl 必须是 http(s) 开头的真实观看页;拿不准就 ok:false,宁缺毋滥。
- 高效:别陷在一道菜上无限搜;候选耗尽就如实 ok:false。
- 最后用 StructuredOutput 返回与 ${metaPath} 一致的结构。`;
}

phase('Acquire');
const results = await parallel(
  indices.map((idx) => () =>
    agent(buildPrompt(idx), {
      label: `vid:${idx}`,
      phase: 'Acquire',
      schema: SCHEMA,
      agentType: 'general-purpose',
    }),
  ),
);

const got = results.filter(Boolean);
const ok = got.filter((r) => r.ok);
log(`acquire 完成:${ok.length}/${indices.length} 条视频外链,${indices.length - ok.length} 条未匹配`);
return { requested: indices.length, ok: ok.length, failed: indices.length - ok.length, results: got };
```

- [ ] **Step 2: 提交脚本(运行在 Task 14)**

```bash
git add apps/recipe-pipeline/data/acquired-videos/acquire-videos.workflow.mjs
git commit -m "feat(recipe-pipeline): 联网搜视频外链 ultracode workflow(每菜一 agent + 相关性校验)"
```

---

## Phase 4:全量重跑 + 补齐(操作 + 检查点)

> 顺序:先全量重清洗(Kimi,只动文本,videoUrl 维持 null)→ 生成菜单 → 跑视频 workflow → videos:apply → gen:seed → 灌 DB。每个改数据的步骤都要 `git diff` 抽检后再继续。

### Task 13: 全量重清洗 364 条(Kimi)

**Files:** 写 `apps/ios/FreshPantry/Resources/howtocook.json`(+ `data/rejects.json`)

- [ ] **Step 1: 确认工作区干净 + .env 就绪**

Run: `git status --short`
Expected: 干净(前序 commit 都已落)。确认 `apps/recipe-pipeline/.env` 有 `CLOUDFLARE_AI_API_KEY`。
> howtocook.json 已 git 提交 = 天然备份,出问题可 `git checkout --` 还原。

- [ ] **Step 2: 全量重清洗**

Run(在 `apps/recipe-pipeline/`):
```bash
npx flue run build-recipes --target node --payload '{"skipImages":true,"refreshDescriptions":true}'
```
Expected: 输出 report,`collected:364`(约),`cleaned` 接近 364,`rejected` 个位数;`skipImages:true` 护住 Supabase 封面 URL(imageUrl 不变);videoUrl 全为 null。运行期可能出现 `[recipes:cf] 重试 …`(容量限流,正常)。

- [ ] **Step 3: 抽检 diff(关键质量门)**

Run:
```bash
git --no-pager diff --stat apps/ios/FreshPantry/Resources/howtocook.json
node -e "const a=require('child_process').execSync('git show HEAD:apps/ios/FreshPantry/Resources/howtocook.json',{cwd:'../..',maxBuffer:1e9}); const before=JSON.parse(a); const after=require('./../ios/FreshPantry/Resources/howtocook.json'); const bi=Object.fromEntries(before.map(r=>[r.id,r])); let img=0,vid=0,cat=0; for(const r of after){const o=bi[r.id]; if(!o)continue; if(o.imageUrl!==r.imageUrl)img++; if((o.category)!==r.category)cat++; if(r.videoUrl!==null)vid++;} console.log('imageUrl 变动:',img,'(应为 0)','category 变动:',cat,'videoUrl 非空:',vid,'(此阶段应为 0)');"
cat data/rejects.json 2>/dev/null | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log('rejects:',JSON.parse(s).length)}catch{console.log('rejects: 0')}})"
```
Expected: **imageUrl 变动 0**(skipImages 生效)、videoUrl 非空 0(此阶段不补视频)、rejects 个位数。category 少量变动可接受;若大量异常漂移,**停下交用户判断**是否回退或换 k2.6。

- [ ] **Step 4: 【检查点】用户确认重清洗质量**

把 `git diff` 的若干条样本(尤其用量结构、步骤)给用户核对。**用户确认后**再继续;否则 `git checkout -- apps/ios/FreshPantry/Resources/howtocook.json data/rejects.json` 还原并与用户商定(换 k2.6 / 调 prompt)。

- [ ] **Step 5: Commit 重清洗结果**

```bash
git add apps/ios/FreshPantry/Resources/howtocook.json apps/recipe-pipeline/data/rejects.json
git commit -m "chore(recipes): Kimi 全量重清洗 364 条(skipImages 护封面,新增 videoUrl 字段)"
```

---

### Task 14: 生成菜单 + 跑视频 workflow + 回写

**Files:** 写 `data/acquired-videos/*`、`apps/ios/FreshPantry/Resources/howtocook.json`、`data/video-attributions.json`

- [ ] **Step 1: 生成全量菜单 `_dishes.json`**

Run(在 `apps/recipe-pipeline/`):
```bash
mkdir -p data/acquired-videos && node -e "const r=require('./../ios/FreshPantry/Resources/howtocook.json'); const d=r.filter(x=>!x.deletedAt).map((x,i)=>({i,id:x.id,name:x.name,category:x.category,ings:(x.ingredients||[]).map(g=>g.name).slice(0,6)})); require('fs').writeFileSync('data/acquired-videos/_dishes.json', JSON.stringify(d,null,2)); console.log('dishes:', d.length);"
```
Expected: 打印 `dishes: 364`(约),生成 `data/acquired-videos/_dishes.json`。索引 `i` 与 workflow 的 `indices` 对应。

- [ ] **Step 2: 跑视频搜集 workflow(ultracode)**

用 Workflow 工具运行 `data/acquired-videos/acquire-videos.workflow.mjs`,`args` 传(绝对路径):
```json
{
  "dishesPath": "/Users/shikun/Developer/opensource/fresh_pantry/apps/recipe-pipeline/data/acquired-videos/_dishes.json",
  "acquiredDir": "/Users/shikun/Developer/opensource/fresh_pantry/apps/recipe-pipeline/data/acquired-videos"
}
```
Expected: 每菜一个 agent 并发跑,产出 `data/acquired-videos/<i>.json`;workflow 末尾 log「acquire 完成:N/364 条视频外链」。失败/未匹配的菜如实 `ok:false`,不硬塞。可先用 `{"indices":[0,1,2]}` 跑 3 条验证管线再全量。
> 这是计费的大 fan-out;先小样后全量。未匹配的可后续 `{"indices":[…]}` 补跑。

- [ ] **Step 3: 回写外链**

Run: `npm run videos:apply`
Expected: 打印「回写 videoUrl N 条」「仍缺视频 M 条」「出处累计 N 条 → data/video-attributions.json」。

- [ ] **Step 4: 抽检 diff**

Run:
```bash
node -e "const r=require('./../ios/FreshPantry/Resources/howtocook.json'); const withVid=r.filter(x=>x.videoUrl); console.log('有视频:',withVid.length,'/',r.length); console.log('样本:',withVid.slice(0,3).map(x=>x.name+' → '+x.videoUrl));"
```
Expected: 有视频条数 = videos:apply 回写数;抽样 URL 是 http(s) 观看页。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Resources/howtocook.json apps/recipe-pipeline/data/video-attributions.json apps/recipe-pipeline/data/acquired-videos
git commit -m "chore(recipes): 联网补齐菜谱视频外链(workflow 搜集 + videos:apply 回写 + 出处)"
```

---

### Task 15: gen:seed + 灌 Supabase

**Files:** 写 `supabase/migrations/20260613120000_recipes_catalog.sql`

- [ ] **Step 1: 重生成种子迁移**

Run(在 `apps/recipe-pipeline/`): `npm run gen:seed`
Expected: 打印 `gen:seed → 364 recipes, … bytes → …/supabase/migrations/20260613120000_recipes_catalog.sql`。迁移内含 `video_url` 列与各行的视频 URL/null。

- [ ] **Step 2: 校验迁移 SQL 含 video_url**

Run: `grep -c "video_url" ../../supabase/migrations/20260613120000_recipes_catalog.sql`
Expected: ≥ 2(DDL 的列定义 + alter + insert 列名)。

- [ ] **Step 3: 应用到 Supabase**

按现有 DB 灌库路径执行(沿用项目既有做法:Management API `/database/query` 直跑该迁移文件 SQL,或 `supabase db push`)。先跑 DDL/alter 让老表加列,再跑 upsert。
> 由于是 `create table if not exists` + `add column if not exists` + `on conflict do update`,幂等可重复应用。⚠️ 灌库前确认操作的是 prod 项目且已知后果(对外可见数据)——征得用户确认再执行。

- [ ] **Step 4: 验证 DB**

Run(Supabase execute_sql 或等价):
```sql
select count(*) total, count(video_url) with_video from public.recipes;
```
Expected: `total` ≈ 364,`with_video` = 回写条数。

- [ ] **Step 5: Commit 迁移**

```bash
git add supabase/migrations/20260613120000_recipes_catalog.sql
git commit -m "chore(db): 重生成 recipes 种子迁移(Kimi 重清洗 + video_url)"
```

---

### Task 16: 全量验证

**Files:** 无

- [ ] **Step 1: pipeline 全测**

Run(在 `apps/recipe-pipeline/`): `npm run typecheck && npx vitest run`
Expected: typecheck 0 error;全部测试绿(含 cloudflare-enricher / fetch-videos / recipe-sql / merge)。

- [ ] **Step 2: iOS 全测 + 编译**

Run:
```bash
cd apps/ios && xcodegen generate && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -25
```
Expected: BUILD SUCCEEDED + 全测试通过(争模拟器导致的 flaky 用 `-only-testing` 或换独立模拟器 by-id 重试)。

- [ ] **Step 3: 真机/模拟器肉眼验视频入口**

打开一条有视频的菜谱详情页,确认「观看视频」按钮出现、点按弹出 in-app Safari 播放外链;无视频的菜不显示按钮。

- [ ] **Step 4: 收尾**

确认所有 commit 已落;若在 worktree/feature 分支,按 `superpowers:finishing-a-development-branch` 决定合并/PR。

---

## Self-Review(已核)

- **Spec 覆盖**:A 模型替换 → Task 1-4;B 视频 schema/回写/workflow → Task 5/7/8/12;C 全量重清洗 → Task 13;D iOS+DB → Task 6/9/10/11;全量重跑补齐 → Task 14/15;测试 → Task 2/5/6/7/9/16。无遗漏。
- **占位符**:无 TODO/TBD;每个改代码的 step 都给了完整代码。
- **类型一致**:`videoUrl`(camel,TS/Swift 模型)↔ `video_url`(snake,DB 列)↔ `videoUrl:video_url`(catalog 别名)一致;`AcquiredVideo`/`VideoAttribution` 在 Task 7 定义、Task 8 引用一致;`createCloudflareEnricher` options 字段(`baseUrl/apiKey/model/maxTokens/maxRetries/fetchImpl/sleep/log`)在 Task 2 定义、Task 3 调用一致(Task 3 已纠正勿传 `concurrency`)。
- **已知偏差(对 spec 的简化)**:merge 不加 `refreshVideos` 旗标(YAGNI——视频由 apply 步既有优先控制,重清洗阶段 f.videoUrl 恒为 null,只需保留 prev)。
