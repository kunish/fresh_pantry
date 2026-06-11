# 菜谱收集 + 清洗管线(Flue)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `apps/recipe-pipeline/` 用 Flue + LLM 重建一条「多源采集 → 清洗增强 → 去重 → 按 id 合并 → 写回 `howtocook.json`」的菜谱管线,取代已删除的 Dart 工具。

**Architecture:** 采集层(可插拔 `RecipeSource`)只产出统一 `RawRecipe`;纯 TS 核心(parser/schema/enrich-assemble/dedup/merge/pipeline)完全可单测、不依赖 flue;LLM 调用藏在 `RecipeEnricher` 接口后,flue 通过 `createAgent` + Valibot 结构化输出实现它。分层方案 C:规整 markdown 仓库走确定性解析,任意 URL 走 LLM 抽取,清洗增强两路共用。

**Tech Stack:** TypeScript(ESM)、`@flue/runtime` + `@flue/cli`(target=node)、`valibot`(结构化输出 + 校验)、`vitest`(对齐 `apps/api`)、Anthropic `claude-sonnet-4-6`。

**关键不变量:** 产物 schema 与现有 363 条完全对齐;按 `id` 合并不覆盖(保住 174 个 `imageUrl`、`remoteVersion`、软删);用量「只抽不猜」;`description` 黏住。详见 `docs/superpowers/specs/2026-06-12-recipe-collection-cleaning-pipeline-design.md`。

---

## 模块清单(决定文件边界)

| 文件 | 职责 | 依赖 flue? |
|---|---|---|
| `src/clean/schema.ts` | Valibot:`CATEGORIES`/`Category`/`CleanRecipeSchema`/`EnrichmentSchema` + 类型 | 否 |
| `src/sources/types.ts` | `RawRecipe`/`RecipeSource`/`SourceContext` 接口 | 否 |
| `src/parse/category-map.ts` | HowToCook 英文目录 → 中文 10 分类 | 否 |
| `src/parse/howtocook-parser.ts` | 确定性 md → `ParsedHowtocook`(原料先剥离再判定、步骤去内联 md) | 否 |
| `src/clean/enrich.ts` | `RecipeEnricher` 接口 + `buildEnrichPrompt` + `assembleRecipe` | 否 |
| `src/clean/dedup.ts` | 跨源去重(规范化名 + 食材 Jaccard + 优先级) | 否 |
| `src/clean/merge.ts` | 按 id 与现有 json 合并(§6 策略表) | 否 |
| `src/util/pool.ts` | 并发限流 `mapWithConcurrency` | 否 |
| `src/util/atomic-write.ts` | 原子写 JSON | 否 |
| `src/config.ts` | 路径/模型/默认源(纯常量 + 路径解析) | 否 |
| `src/pipeline.ts` | 纯编排:collect→enrich→assemble→dedup→merge→write→report | 否 |
| `src/sources/howtocook.ts` | HowToCook 采集适配器(浅克隆 + 遍历 + parser) | 否 |
| `src/sources/markdown-repo.ts` | 通用中文菜谱 markdown 仓库适配器 | 否 |
| `src/sources/url-batch.ts` | 任意 URL 抓页 → `rawText`(LLM 抽取) | 否 |
| `src/sources/registry.ts` | 配置驱动的 source 实例化 | 否 |
| `src/agents/recipe-cleaner.ts` | `createAgent`:清洗增强 agent(指令 + 模型) | 是 |
| `src/clean/flue-enricher.ts` | 用 harness/session 实现 `RecipeEnricher` | 是 |
| `src/workflows/build-recipes.ts` | flue workflow:wire 源 + flue enricher + 跑 pipeline | 是 |

**纯 TS 核心(前 13 个,不依赖 flue)在 Milestone 1–5 全部 TDD 完成并可单测;flue 胶水(后 3 个)在 Milestone 6;额外适配器在 Milestone 7。**

---

## Milestone 0:工程脚手架

### Task 0.1:初始化 Flue 工程

**Files:**
- Create: `apps/recipe-pipeline/package.json`
- Create: `apps/recipe-pipeline/tsconfig.json`
- Create: `apps/recipe-pipeline/vitest.config.ts`
- Create: `apps/recipe-pipeline/flue.config.ts`
- Create: `apps/recipe-pipeline/.gitignore`
- Create: `apps/recipe-pipeline/.env.example`

- [ ] **Step 1: 建目录并装依赖**

```bash
mkdir -p apps/recipe-pipeline
cd apps/recipe-pipeline
npm init -y
npm install @flue/runtime valibot
npm install --save-dev @flue/cli vitest typescript @types/node
```

- [ ] **Step 2: 写 `package.json`**(覆盖 `npm init` 产物)

```json
{
  "name": "@fresh-pantry/recipe-pipeline",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc --noEmit",
    "build:recipes": "flue run build-recipes --target node --payload '{}'",
    "build:recipes:dry": "flue run build-recipes --target node --payload '{\"dryRun\":true}'"
  }
}
```

> 依赖版本以 `npm install` 实际写入为准;不要手填版本号。

- [ ] **Step 3: 写 `tsconfig.json`**(对齐 `apps/api` 风格,改为可运行 node ESM)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "types": ["node"],
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "resolveJsonModule": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src", "test", "vitest.config.ts", "flue.config.ts"]
}
```

- [ ] **Step 4: 写 `vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: { include: ['test/**/*.test.ts'] },
});
```

- [ ] **Step 5: 写 `flue.config.ts`**

```ts
import { defineConfig } from '@flue/cli/config';

export default defineConfig({
  output: './build',
});
```

- [ ] **Step 6: 写 `.gitignore` 与 `.env.example`**

`.gitignore`:
```
node_modules/
build/
dist/
.flue/
.env
.cache/
```

`.env.example`:
```
ANTHROPIC_API_KEY="your-api-key"
```

- [ ] **Step 7: 冒烟校验脚手架可编译**

Run: `cd apps/recipe-pipeline && npx tsc --noEmit`
Expected: 无报错(此时无源码,空通过)。

- [ ] **Step 8: Commit**

```bash
git add apps/recipe-pipeline/package.json apps/recipe-pipeline/tsconfig.json apps/recipe-pipeline/vitest.config.ts apps/recipe-pipeline/flue.config.ts apps/recipe-pipeline/.gitignore apps/recipe-pipeline/.env.example apps/recipe-pipeline/package-lock.json
git commit -m "chore(recipe-pipeline): scaffold flue project"
```

---

## Milestone 1:Schema、类型、分类映射(纯 TS 基础)

### Task 1.1:输出契约 Schema(Valibot)

**Files:**
- Create: `apps/recipe-pipeline/src/clean/schema.ts`
- Test: `apps/recipe-pipeline/test/schema.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// test/schema.test.ts
import { describe, it, expect } from 'vitest';
import * as v from 'valibot';
import { CleanRecipeSchema, CATEGORIES } from '../src/clean/schema';

const valid = {
  id: 'howtocook:vegetable_dish/凉拌黄瓜',
  name: '凉拌黄瓜',
  category: '素菜',
  difficulty: 1,
  cookingMinutes: 20,
  description: '清爽开胃',
  ingredients: [{ name: '黄瓜', quantity: '200', unit: '克', amount: '200 克' }],
  steps: ['拍碎'],
  tags: ['素菜'],
  imageUrl: null,
  remoteVersion: 0,
  clientUpdatedAt: null,
  deletedAt: null,
};

describe('CleanRecipeSchema', () => {
  it('接受合法记录', () => {
    expect(() => v.parse(CleanRecipeSchema, valid)).not.toThrow();
  });
  it('拒绝非法分类', () => {
    expect(() => v.parse(CleanRecipeSchema, { ...valid, category: '夜宵' })).toThrow();
  });
  it('拒绝难度越界', () => {
    expect(() => v.parse(CleanRecipeSchema, { ...valid, difficulty: 6 })).toThrow();
  });
  it('CATEGORIES 恰为 10 个', () => {
    expect(CATEGORIES).toHaveLength(10);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/schema.test.ts`
Expected: FAIL — `Cannot find module '../src/clean/schema'`。

- [ ] **Step 3: 实现 `schema.ts`**

```ts
// src/clean/schema.ts
import * as v from 'valibot';

export const CATEGORIES = [
  '主食', '半成品', '早餐', '水产', '汤羹', '甜品', '素菜', '荤菜', '酱料', '饮品',
] as const;

export type Category = (typeof CATEGORIES)[number];

export const IngredientSchema = v.object({
  name: v.pipe(v.string(), v.minLength(1)),
  quantity: v.string(),
  unit: v.string(),
  amount: v.string(),
});

export const CleanRecipeSchema = v.object({
  id: v.pipe(v.string(), v.minLength(1)),
  name: v.pipe(v.string(), v.minLength(1)),
  category: v.picklist(CATEGORIES),
  difficulty: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(5)),
  cookingMinutes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  description: v.string(),
  ingredients: v.array(IngredientSchema),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
  imageUrl: v.nullable(v.string()),
  remoteVersion: v.pipe(v.number(), v.integer()),
  clientUpdatedAt: v.nullable(v.string()),
  deletedAt: v.nullable(v.string()),
});

export type CleanRecipe = v.InferOutput<typeof CleanRecipeSchema>;

// LLM 可拥有的字段(URL 源全交给它;确定性源仅取其 amounts/cookingMinutes/tags/desc 兜底)
export const EnrichmentSchema = v.object({
  category: v.picklist(CATEGORIES),
  difficulty: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(5)),
  cookingMinutes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  description: v.string(),
  ingredients: v.array(IngredientSchema),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
});

export type Enrichment = v.InferOutput<typeof EnrichmentSchema>;
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/schema.test.ts`
Expected: PASS(4 个)。

- [ ] **Step 5: 用真实数据加固(读现有 json 第一条)**

追加到 `test/schema.test.ts`:
```ts
import recipes from '../../ios/FreshPantry/Resources/howtocook.json';

it('接受真实 howtocook.json 首条', () => {
  expect(() => v.parse(CleanRecipeSchema, (recipes as unknown[])[0])).not.toThrow();
});
```

> 路径:`apps/recipe-pipeline/test/` 到 `apps/ios/FreshPantry/Resources/howtocook.json` 的相对路径为 `../../ios/FreshPantry/Resources/howtocook.json`。需 `resolveJsonModule`(已开)。若 vitest 对大 JSON import 报错,改用 `fs.readFileSync` + `JSON.parse`。

Run: `npx vitest run test/schema.test.ts`
Expected: PASS(5 个)。

- [ ] **Step 6: Commit**

```bash
git add apps/recipe-pipeline/src/clean/schema.ts apps/recipe-pipeline/test/schema.test.ts
git commit -m "feat(recipe-pipeline): CleanRecipe/Enrichment valibot schema"
```

### Task 1.2:采集层类型

**Files:**
- Create: `apps/recipe-pipeline/src/sources/types.ts`

- [ ] **Step 1: 实现 `types.ts`**(纯接口,无需测试)

```ts
// src/sources/types.ts
export interface RawRecipe {
  id: string;                  // 各源自定 id 方案;确定性可复现
  sourceId: string;            // "howtocook" | "repo:<name>" | "url"
  sourceRef: string;          // 文件路径或 URL —— 溯源
  name: string;
  sourceCategory?: string;     // 源已知的中文分类(适配器已映射)
  sourceDifficulty?: number;   // 源已知难度 1-5
  description?: string;        // 解析到的描述(若有)
  rawIngredients: string[];    // 食材名(工具已剥离)
  portionText?: string;        // 计算/总量段 —— 用量来源(只抽不猜)
  steps: string[];             // 已清洗步骤(确定性源)
  rawText?: string;            // 仅 Tier2 URL:整页正文
  imageUrl?: string | null;
}

export interface SourceContext {
  workDir: string;             // 缓存/克隆工作目录
  log: (msg: string) => void;
}

export interface RecipeSource {
  id: string;
  kind: 'deterministic' | 'llm-extract';
  collect(ctx: SourceContext): AsyncIterable<RawRecipe>;
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/recipe-pipeline/src/sources/types.ts
git commit -m "feat(recipe-pipeline): RawRecipe/RecipeSource types"
```

### Task 1.3:HowToCook 分类映射

**Files:**
- Create: `apps/recipe-pipeline/src/parse/category-map.ts`
- Test: `apps/recipe-pipeline/test/category-map.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// test/category-map.test.ts
import { describe, it, expect } from 'vitest';
import { mapHowtocookCategory, HOWTOCOOK_CATEGORY_MAP } from '../src/parse/category-map';

describe('mapHowtocookCategory', () => {
  it('全部 10 个英文目录都有映射', () => {
    expect(Object.keys(HOWTOCOOK_CATEGORY_MAP)).toHaveLength(10);
  });
  it.each([
    ['aquatic', '水产'], ['breakfast', '早餐'], ['condiment', '酱料'],
    ['dessert', '甜品'], ['drink', '饮品'], ['meat_dish', '荤菜'],
    ['semi-finished', '半成品'], ['soup', '汤羹'], ['staple', '主食'],
    ['vegetable_dish', '素菜'],
  ])('%s -> %s', (en, zh) => {
    expect(mapHowtocookCategory(en)).toBe(zh);
  });
  it('未知目录返回 undefined', () => {
    expect(mapHowtocookCategory('unknown')).toBeUndefined();
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/category-map.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `category-map.ts`**

```ts
// src/parse/category-map.ts
import type { Category } from '../clean/schema';

export const HOWTOCOOK_CATEGORY_MAP: Record<string, Category> = {
  aquatic: '水产',
  breakfast: '早餐',
  condiment: '酱料',
  dessert: '甜品',
  drink: '饮品',
  meat_dish: '荤菜',
  'semi-finished': '半成品',
  soup: '汤羹',
  staple: '主食',
  vegetable_dish: '素菜',
};

export function mapHowtocookCategory(dir: string): Category | undefined {
  return HOWTOCOOK_CATEGORY_MAP[dir];
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/category-map.test.ts`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/parse/category-map.ts apps/recipe-pipeline/test/category-map.test.ts
git commit -m "feat(recipe-pipeline): howtocook category map"
```

---

## Milestone 2:HowToCook 确定性解析器

### Task 2.1:vendored 真实 fixture

**Files:**
- Create: `apps/recipe-pipeline/test/fixtures/howtocook/凉拌黄瓜.md`
- Create: `apps/recipe-pipeline/test/fixtures/howtocook/带工具样本.md`

- [ ] **Step 1: 下载一份真实直挂 md**

```bash
cd apps/recipe-pipeline
mkdir -p test/fixtures/howtocook
curl -s "https://raw.githubusercontent.com/Anduin2017/HowToCook/master/dishes/vegetable_dish/%E5%87%89%E6%8B%8C%E9%BB%84%E7%93%9C.md" -o "test/fixtures/howtocook/凉拌黄瓜.md"
test -s "test/fixtures/howtocook/凉拌黄瓜.md" && head -1 "test/fixtures/howtocook/凉拌黄瓜.md"
```
Expected: 打印 `# 凉拌黄瓜的做法`。

- [ ] **Step 2: 手写一份「含工具」fixture**(验证「先剥离再判定」)

写入 `test/fixtures/howtocook/带工具样本.md`:
```markdown
# 测试菜的做法

一句话描述。

预估烹饪难度：★★★

## 必备原料和工具

* 鸡蛋
* 西红柿
* 一个不粘锅
* 炒勺
* 盐

## 操作

1. 打蛋
2. **翻炒**至熟

## 附加内容

* 备注
```

- [ ] **Step 3: Commit**

```bash
git add apps/recipe-pipeline/test/fixtures/howtocook/
git commit -m "test(recipe-pipeline): vendor howtocook markdown fixtures"
```

### Task 2.2:解析器

**Files:**
- Create: `apps/recipe-pipeline/src/parse/howtocook-parser.ts`
- Test: `apps/recipe-pipeline/test/howtocook-parser.test.ts`

- [ ] **Step 1: 写失败测试**(golden + 工具剥离 + 步骤清洗)

```ts
// test/howtocook-parser.test.ts
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { parseHowtocook, isTool, stripInlineMarkdown } from '../src/parse/howtocook-parser';

const here = dirname(fileURLToPath(import.meta.url));
const fx = (n: string) => readFileSync(join(here, 'fixtures/howtocook', n), 'utf8');

describe('parseHowtocook', () => {
  it('凉拌黄瓜:名称/难度/原料/步骤/描述/计算段', () => {
    const r = parseHowtocook(fx('凉拌黄瓜.md'));
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.difficulty).toBe(1);
    expect(r.rawIngredients).toEqual(['黄瓜', '醋', '酱油', '蒜']);
    expect(r.steps).toHaveLength(6);
    expect(r.steps[0]).toContain('黄瓜拍扁');
    expect(r.description).toContain('清爽开胃');
    expect(r.portionText).toContain('黄瓜 200 克');
  });

  it('带工具样本:剥离锅/勺,保留食材;步骤去内联 markdown', () => {
    const r = parseHowtocook(fx('带工具样本.md'));
    expect(r.difficulty).toBe(3);
    expect(r.rawIngredients).toEqual(['鸡蛋', '西红柿', '盐']);
    expect(r.steps[1]).toBe('翻炒至熟'); // ** 去掉
  });
});

describe('isTool', () => {
  it.each(['一个不粘锅', '炒勺', '菜刀', '案板'])('%s 是工具', (s) => {
    expect(isTool(s)).toBe(true);
  });
  it.each(['鸡蛋', '西红柿', '盐', '黄瓜'])('%s 不是工具', (s) => {
    expect(isTool(s)).toBe(false);
  });
});

describe('stripInlineMarkdown', () => {
  it('去 ** _ ` 链接', () => {
    expect(stripInlineMarkdown('**翻炒**至 _熟_')).toBe('翻炒至 熟');
    expect(stripInlineMarkdown('见 [图](http://x)')).toBe('见 图');
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/howtocook-parser.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `howtocook-parser.ts`**

```ts
// src/parse/howtocook-parser.ts
export interface ParsedHowtocook {
  name: string;
  difficulty: number;        // 1-5
  description?: string;
  rawIngredients: string[];
  portionText?: string;
  steps: string[];
}

// 工具关键词:出现即视为工具(必备原料段里工具与食材是分行的,误伤风险低)
export const TOOL_KEYWORDS = [
  '锅', '铲', '勺', '刀', '案板', '砧板', '菜板', '碗', '盆', '筷', '烤箱',
  '微波炉', '电饭煲', '空气炸锅', '高压锅', '料理机', '搅拌机', '榨汁',
  '量杯', '量勺', '厨房秤', '电子秤', '保鲜膜', '锡纸', '油纸', '牙签',
  '厨房纸', '吸油纸', '喷壶', '刷子', '夹子', '漏勺', '蒸笼', '蒸架',
  '烤盘', '模具', '裱花', '擀面杖', '筛',
];

export function isTool(line: string): boolean {
  return TOOL_KEYWORDS.some((kw) => line.includes(kw));
}

export function stripInlineMarkdown(s: string): string {
  return s
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1') // [文本](url) / 图片 -> 文本
    .replace(/[*_`]+/g, '')                     // ** _ ` 等强调符
    .replace(/\s+/g, ' ')
    .trim();
}

function bulletLines(block: string): string[] {
  return block
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => /^([*\-]|\d+\.)\s+/.test(l))
    .map((l) => l.replace(/^([*\-]|\d+\.)\s+/, '').trim());
}

interface Section {
  heading: string;
  body: string;
}

function splitSections(md: string): { preamble: string; sections: Section[] } {
  const parts = md.split(/^##\s+/m);
  const preamble = parts[0];
  const sections = parts.slice(1).map((p) => {
    const nl = p.indexOf('\n');
    return nl === -1
      ? { heading: p.trim(), body: '' }
      : { heading: p.slice(0, nl).trim(), body: p.slice(nl + 1) };
  });
  return { preamble, sections };
}

export function parseHowtocook(markdown: string): ParsedHowtocook {
  const { preamble, sections } = splitSections(markdown);

  // 名称:# X的做法
  const titleMatch = preamble.match(/^#\s+(.+?)\s*$/m);
  const rawTitle = titleMatch ? titleMatch[1].trim() : '';
  const name = rawTitle.replace(/的做法\s*$/, '').trim();

  // 难度:预估烹饪难度:★...
  const starMatch = preamble.match(/预估烹饪难度[:：]\s*(★+)/);
  const difficulty = starMatch ? Math.min(5, starMatch[1].length) : 3;

  // 描述:标题之后、第一个「预估/##」之前的正文段落
  const descLines: string[] = [];
  for (const line of preamble.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    if (t.startsWith('预估')) break;
    descLines.push(t);
  }
  const description = descLines.length ? descLines.join(' ') : undefined;

  const find = (kw: string) => sections.find((s) => s.heading.includes(kw));

  // 原料:先剥离工具,再判定
  const ingSection = find('必备原料') ?? find('原料');
  const rawIngredients = ingSection
    ? bulletLines(ingSection.body).filter((l) => !isTool(l))
    : [];

  // 计算/总量段:用量来源
  const calcSection = find('计算');
  const portionText = calcSection ? calcSection.body.trim() || undefined : undefined;

  // 步骤:操作段
  const opSection = find('操作') ?? find('步骤');
  const steps = opSection ? bulletLines(opSection.body).map(stripInlineMarkdown) : [];

  return { name, difficulty, description, rawIngredients, portionText, steps };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/howtocook-parser.test.ts`
Expected: PASS(全部)。若 golden 断言因真实 md 细节(空格/标点)略不符,以 fixture 实际内容为准微调断言,不要改解析逻辑去迁就。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/parse/howtocook-parser.ts apps/recipe-pipeline/test/howtocook-parser.test.ts
git commit -m "feat(recipe-pipeline): deterministic howtocook markdown parser"
```

---

## Milestone 3:清洗增强(prompt + 组装,stub 模型)

### Task 3.1:`RecipeEnricher` 接口、prompt 构造、记录组装

**Files:**
- Create: `apps/recipe-pipeline/src/clean/enrich.ts`
- Test: `apps/recipe-pipeline/test/enrich.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// test/enrich.test.ts
import { describe, it, expect } from 'vitest';
import { buildEnrichPrompt, assembleRecipe } from '../src/clean/enrich';
import type { RawRecipe } from '../src/sources/types';
import type { Enrichment } from '../src/clean/schema';

const tier1: RawRecipe = {
  id: 'howtocook:vegetable_dish/凉拌黄瓜',
  sourceId: 'howtocook',
  sourceRef: 'dishes/vegetable_dish/凉拌黄瓜.md',
  name: '凉拌黄瓜',
  sourceCategory: '素菜',
  sourceDifficulty: 1,
  description: '清爽开胃',
  rawIngredients: ['黄瓜', '醋'],
  portionText: '黄瓜 200 克 * 份数\n醋 7.5 ml * 份数',
  steps: ['拍碎', '调味'],
  imageUrl: null,
};

const enr: Enrichment = {
  category: '荤菜', // 故意与 sourceCategory 不同,验证确定性优先
  difficulty: 4,    // 同上
  cookingMinutes: 20,
  description: 'LLM 写的',
  ingredients: [
    { name: '黄瓜', quantity: '200', unit: '克', amount: '200 克' },
    { name: '醋', quantity: '7.5', unit: 'ml', amount: '7.5 ml' },
  ],
  steps: ['LLM步骤'],
  tags: ['爽口'],
};

describe('buildEnrichPrompt', () => {
  it('Tier1 含原料、计算段,并强调只抽不猜', () => {
    const p = buildEnrichPrompt(tier1);
    expect(p).toContain('黄瓜 200 克');
    expect(p).toContain('凉拌黄瓜');
    expect(p).toMatch(/只.*源文本写了才填|不要(编造|估算|猜)/);
  });
  it('Tier2 走 rawText 抽取', () => {
    const p = buildEnrichPrompt({ ...tier1, rawText: '网页正文…', portionText: undefined });
    expect(p).toContain('网页正文');
  });
});

describe('assembleRecipe', () => {
  it('确定性字段优先:分类/难度/描述/步骤来自 raw,用量来自 enrichment', () => {
    const r = assembleRecipe(tier1, enr);
    expect(r.id).toBe(tier1.id);
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.category).toBe('素菜');     // sourceCategory 优先
    expect(r.difficulty).toBe(1);        // sourceDifficulty 优先
    expect(r.description).toBe('清爽开胃'); // raw.description 优先
    expect(r.steps).toEqual(['拍碎', '调味']); // raw.steps 优先
    expect(r.ingredients[0].amount).toBe('200 克'); // 用量来自 enrichment
    expect(r.tags).toContain('素菜');
    expect(r.remoteVersion).toBe(0);
    expect(r.clientUpdatedAt).toBeNull();
    expect(r.deletedAt).toBeNull();
  });
  it('URL 源缺确定性字段时回落 enrichment', () => {
    const url: RawRecipe = {
      id: 'url:example', sourceId: 'url', sourceRef: 'http://x',
      name: '番茄炒蛋', rawIngredients: [], steps: [], rawText: '…',
    };
    const r = assembleRecipe(url, enr);
    expect(r.category).toBe('荤菜');     // 回落 enrichment
    expect(r.difficulty).toBe(4);
    expect(r.description).toBe('LLM 写的');
    expect(r.steps).toEqual(['LLM步骤']);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/enrich.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `enrich.ts`**

```ts
// src/clean/enrich.ts
import type { RawRecipe } from '../sources/types';
import { CATEGORIES, type CleanRecipe, type Enrichment } from './schema';

export interface RecipeEnricher {
  enrich(raw: RawRecipe): Promise<Enrichment>;
}

export const RECIPE_CLEANER_INSTRUCTIONS = `你是中文家常菜谱清洗助手。把输入整理成结构化菜谱字段。规则:
- 分类必须取自:${CATEGORIES.join('、')}。
- 食材用量「只抽不猜」:quantity/unit/amount 仅当源文本(尤其「计算/总量」段)明确写了才填,源没写就一律留空字符串,严禁估算或编造。
- difficulty 取 1-5 整数;cookingMinutes 取正整数(可据步骤数与描述合理估算时长)。
- description:若已提供则原样沿用,否则写一两句简介。
- 只返回符合 schema 的结构化结果。`;

export function buildEnrichPrompt(raw: RawRecipe): string {
  if (raw.rawText) {
    return [
      `从以下网页正文抽取一道中文菜谱。名称参考:「${raw.name}」。`,
      `严格遵守「只抽不猜」:用量只在正文写明时才填。`,
      `分类必须取自:${CATEGORIES.join('、')}。`,
      `--- 网页正文 ---`,
      raw.rawText,
    ].join('\n');
  }
  return [
    `清洗下面这道菜谱「${raw.name}」。`,
    raw.sourceCategory ? `分类:${raw.sourceCategory}(沿用)。` : `请归类到 10 个分类之一。`,
    raw.sourceDifficulty ? `难度:${raw.sourceDifficulty}(沿用)。` : ``,
    `食材名:${raw.rawIngredients.join('、') || '(无)'}`,
    `步骤:`,
    ...raw.steps.map((s, i) => `${i + 1}. ${s}`),
    `--- 计算/总量段(用量来源,只抽不猜) ---`,
    raw.portionText ?? '(源未提供用量,ingredients 的 quantity/unit/amount 全部留空字符串)',
    raw.description ? `已有描述(沿用):${raw.description}` : `请补写一两句描述。`,
    `把每个食材名映射到用量(只从上面的计算段抽,抽不到就留空)。`,
  ].filter(Boolean).join('\n');
}

function uniq(xs: string[]): string[] {
  return [...new Set(xs.filter(Boolean))];
}

export function assembleRecipe(raw: RawRecipe, enr: Enrichment): CleanRecipe {
  const category = (raw.sourceCategory as CleanRecipe['category']) ?? enr.category;
  const difficulty = raw.sourceDifficulty ?? enr.difficulty;
  const description = raw.description?.trim() || enr.description;
  const steps = raw.steps.length ? raw.steps : enr.steps;
  return {
    id: raw.id,
    name: raw.name,
    category,
    difficulty,
    cookingMinutes: enr.cookingMinutes,
    description,
    ingredients: enr.ingredients,
    steps,
    tags: uniq([category, ...enr.tags]),
    imageUrl: raw.imageUrl ?? null,
    remoteVersion: 0,
    clientUpdatedAt: null,
    deletedAt: null,
  };
}
```

> 注:`category` 一定会经 `CleanRecipeSchema` 在写盘前校验(Task 5),非法值会被拦下进 rejects。

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/enrich.test.ts`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/clean/enrich.ts apps/recipe-pipeline/test/enrich.test.ts
git commit -m "feat(recipe-pipeline): enrich prompt + recipe assembly (deterministic-first)"
```

---

## Milestone 4:去重 + 合并(数据安全核心)

### Task 4.1:跨源去重

**Files:**
- Create: `apps/recipe-pipeline/src/clean/dedup.ts`
- Test: `apps/recipe-pipeline/test/dedup.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// test/dedup.test.ts
import { describe, it, expect } from 'vitest';
import { normalizeName, jaccard, dedupe } from '../src/clean/dedup';
import type { CleanRecipe } from '../src/clean/schema';

function rec(id: string, name: string, ings: string[]): CleanRecipe {
  return {
    id, name, category: '荤菜', difficulty: 2, cookingMinutes: 20,
    description: '', ingredients: ings.map((n) => ({ name: n, quantity: '', unit: '', amount: '' })),
    steps: [], tags: [], imageUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null,
  };
}

describe('normalizeName', () => {
  it('去空白/全半角/标点', () => {
    expect(normalizeName(' 番茄炒蛋（家常）')).toBe('番茄炒蛋家常');
    expect(normalizeName('番茄炒蛋')).toBe('番茄炒蛋');
  });
});

describe('jaccard', () => {
  it('交并比', () => {
    expect(jaccard(new Set(['a', 'b']), new Set(['a', 'b']))).toBe(1);
    expect(jaccard(new Set(['a', 'b', 'c', 'd']), new Set(['a']))).toBeCloseTo(0.25);
  });
});

describe('dedupe', () => {
  it('同名 + 食材高度重合 -> 留高优先级(howtocook),丢低优先', () => {
    const hc = rec('howtocook:meat_dish/番茄炒蛋', '番茄炒蛋', ['番茄', '鸡蛋', '盐']);
    const url = rec('url:abc', '番茄炒蛋', ['番茄', '鸡蛋', '糖']);
    const { kept, dropped } = dedupe([url, hc]); // 乱序输入
    expect(kept.map((r) => r.id)).toEqual(['howtocook:meat_dish/番茄炒蛋']);
    expect(dropped).toEqual([{ id: 'url:abc', dupOf: 'howtocook:meat_dish/番茄炒蛋' }]);
  });
  it('同名但食材差异大 -> 都保留', () => {
    const a = rec('repo:x:糖醋里脊', '糖醋里脊', ['里脊', '糖', '醋']);
    const b = rec('url:y', '糖醋里脊', ['豆腐', '酱油']);
    const { kept } = dedupe([a, b]);
    expect(kept).toHaveLength(2);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/dedup.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `dedup.ts`**

```ts
// src/clean/dedup.ts
import type { CleanRecipe } from './schema';

// 源优先级:数值小者优先保留
const PRIORITY: Array<[string, number]> = [
  ['howtocook:', 0],
  ['repo:', 1],
  ['url:', 2],
];

function sourcePriority(id: string): number {
  const hit = PRIORITY.find(([prefix]) => id.startsWith(prefix));
  return hit ? hit[1] : 99;
}

export function normalizeName(name: string): string {
  return name
    .normalize('NFKC')                         // 全角 -> 半角
    .replace(/[\s　]/g, '')                // 去空白(含全角空格)
    .replace(/[（）()【】\[\]「」『』·・,，。.、！!？?~～\-—_]/g, '')
    .toLowerCase();
}

export function ingredientSet(r: CleanRecipe): Set<string> {
  return new Set(r.ingredients.map((i) => i.name.trim()).filter(Boolean));
}

export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  const union = a.size + b.size - inter;
  return union === 0 ? 0 : inter / union;
}

export const DUP_THRESHOLD = 0.6;

export interface DedupeResult {
  kept: CleanRecipe[];
  dropped: Array<{ id: string; dupOf: string }>;
}

export function dedupe(recipes: CleanRecipe[]): DedupeResult {
  // 高优先级先进 kept
  const ordered = [...recipes].sort((a, b) => sourcePriority(a.id) - sourcePriority(b.id));
  const kept: CleanRecipe[] = [];
  const dropped: Array<{ id: string; dupOf: string }> = [];
  for (const r of ordered) {
    const key = normalizeName(r.name);
    const set = ingredientSet(r);
    const dupOf = kept.find(
      (k) => normalizeName(k.name) === key && jaccard(ingredientSet(k), set) >= DUP_THRESHOLD,
    );
    if (dupOf) dropped.push({ id: r.id, dupOf: dupOf.id });
    else kept.push(r);
  }
  return { kept, dropped };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/dedup.test.ts`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/clean/dedup.ts apps/recipe-pipeline/test/dedup.test.ts
git commit -m "feat(recipe-pipeline): cross-source dedupe by name + ingredient jaccard"
```

### Task 4.2:按 id 合并现有 json(§6 策略表)

**Files:**
- Create: `apps/recipe-pipeline/src/clean/merge.ts`
- Test: `apps/recipe-pipeline/test/merge.test.ts`

- [ ] **Step 1: 写失败测试**(逐条验策略表 —— 最高价值)

```ts
// test/merge.test.ts
import { describe, it, expect } from 'vitest';
import { mergeWithExisting } from '../src/clean/merge';
import type { CleanRecipe } from '../src/clean/schema';

function rec(over: Partial<CleanRecipe> & { id: string }): CleanRecipe {
  return {
    id: over.id, name: over.name ?? '菜', category: over.category ?? '荤菜',
    difficulty: over.difficulty ?? 2, cookingMinutes: over.cookingMinutes ?? 20,
    description: over.description ?? '', ingredients: over.ingredients ?? [],
    steps: over.steps ?? [], tags: over.tags ?? [], imageUrl: over.imageUrl ?? null,
    remoteVersion: over.remoteVersion ?? 0, clientUpdatedAt: over.clientUpdatedAt ?? null,
    deletedAt: over.deletedAt ?? null,
  };
}
const NOW = '2026-06-12T00:00:00.000Z';

describe('mergeWithExisting', () => {
  it('imageUrl 既有优先;amount 回填;description 黏住;remoteVersion 保留', () => {
    const existing = [rec({
      id: 'a', imageUrl: 'https://img/a.jpg', description: '老描述', remoteVersion: 7,
      ingredients: [{ name: '蛋', quantity: '', unit: '', amount: '' }],
    })];
    const fresh = [rec({
      id: 'a', imageUrl: null, description: '新描述', remoteVersion: 0,
      ingredients: [{ name: '蛋', quantity: '2', unit: '个', amount: '2 个' }],
    })];
    const { merged, stats } = mergeWithExisting(fresh, existing, NOW);
    const a = merged.find((r) => r.id === 'a')!;
    expect(a.imageUrl).toBe('https://img/a.jpg');     // 既有优先
    expect(a.description).toBe('老描述');               // 黏住
    expect(a.remoteVersion).toBe(7);                   // 保留
    expect(a.ingredients[0].amount).toBe('2 个');       // 回填
    expect(stats.updated).toBe(1);
  });

  it('refreshDescriptions 时才覆盖描述', () => {
    const existing = [rec({ id: 'a', description: '老描述' })];
    const fresh = [rec({ id: 'a', description: '新描述' })];
    const { merged } = mergeWithExisting(fresh, existing, NOW, { refreshDescriptions: true });
    expect(merged[0].description).toBe('新描述');
  });

  it('既有描述为空 -> 用新描述', () => {
    const existing = [rec({ id: 'a', description: '' })];
    const fresh = [rec({ id: 'a', description: '新描述' })];
    const { merged } = mergeWithExisting(fresh, existing, NOW);
    expect(merged[0].description).toBe('新描述');
  });

  it('软删的菜不复活、不被改写', () => {
    const existing = [rec({ id: 'a', deletedAt: '2026-01-01T00:00:00.000Z', name: '旧名' })];
    const fresh = [rec({ id: 'a', deletedAt: null, name: '新名' })];
    const { merged, stats } = mergeWithExisting(fresh, existing, NOW);
    expect(merged[0].deletedAt).toBe('2026-01-01T00:00:00.000Z');
    expect(merged[0].name).toBe('旧名');
    expect(stats.updated).toBe(0);
  });

  it('新菜:remoteVersion 0、clientUpdatedAt/deletedAt null', () => {
    const { merged, stats } = mergeWithExisting([rec({ id: 'b' })], [], NOW);
    expect(stats.added).toBe(1);
    expect(merged[0].remoteVersion).toBe(0);
    expect(merged[0].clientUpdatedAt).toBeNull();
  });

  it('本轮未触及的既有菜原样保留', () => {
    const existing = [rec({ id: 'a' }), rec({ id: 'keep' })];
    const { merged } = mergeWithExisting([rec({ id: 'a' })], existing, NOW);
    expect(merged.map((r) => r.id).sort()).toEqual(['a', 'keep']);
  });

  it('输出按 id 稳定排序', () => {
    const { merged } = mergeWithExisting([rec({ id: 'c' }), rec({ id: 'a' })], [rec({ id: 'b' })], NOW);
    expect(merged.map((r) => r.id)).toEqual(['a', 'b', 'c']);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/merge.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `merge.ts`**

```ts
// src/clean/merge.ts
import type { CleanRecipe } from './schema';

export interface MergeOptions {
  refreshDescriptions?: boolean;
}

export interface MergeResult {
  merged: CleanRecipe[];
  stats: { added: number; updated: number; unchanged: number };
}

export function mergeWithExisting(
  fresh: CleanRecipe[],
  existing: CleanRecipe[],
  now: string,
  opts: MergeOptions = {},
): MergeResult {
  void now; // 当前新菜沿用 seed 约定(clientUpdatedAt=null);保留入参以备将来 bump 策略
  const byId = new Map<string, CleanRecipe>(existing.map((r) => [r.id, r]));
  const stats = { added: 0, updated: 0, unchanged: 0 };

  for (const f of fresh) {
    const prev = byId.get(f.id);
    if (!prev) {
      byId.set(f.id, { ...f, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null });
      stats.added++;
      continue;
    }
    if (prev.deletedAt) {
      stats.unchanged++; // 软删的不复活、不改写
      continue;
    }
    const description =
      prev.description && !opts.refreshDescriptions ? prev.description : f.description;
    byId.set(f.id, {
      ...f,
      imageUrl: prev.imageUrl ?? f.imageUrl,
      description,
      remoteVersion: prev.remoteVersion,
      clientUpdatedAt: prev.clientUpdatedAt,
      deletedAt: prev.deletedAt,
    });
    stats.updated++;
  }

  const merged = [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
  return { merged, stats };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/merge.test.ts`
Expected: PASS(全部)。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/clean/merge.ts apps/recipe-pipeline/test/merge.test.ts
git commit -m "feat(recipe-pipeline): merge-with-existing preserving images/version/soft-delete"
```

---

## Milestone 5:管线编排(纯,stub 模型端到端)

### Task 5.1:工具:并发限流 + 原子写

**Files:**
- Create: `apps/recipe-pipeline/src/util/pool.ts`
- Create: `apps/recipe-pipeline/src/util/atomic-write.ts`
- Test: `apps/recipe-pipeline/test/pool.test.ts`

- [ ] **Step 1: 写失败测试(pool)**

```ts
// test/pool.test.ts
import { describe, it, expect } from 'vitest';
import { mapWithConcurrency } from '../src/util/pool';

describe('mapWithConcurrency', () => {
  it('保持输入顺序、限并发', async () => {
    let active = 0;
    let maxActive = 0;
    const out = await mapWithConcurrency([1, 2, 3, 4, 5], 2, async (n) => {
      active++; maxActive = Math.max(maxActive, active);
      await new Promise((r) => setTimeout(r, 5));
      active--;
      return n * 10;
    });
    expect(out).toEqual([10, 20, 30, 40, 50]);
    expect(maxActive).toBeLessThanOrEqual(2);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/pool.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `pool.ts` 与 `atomic-write.ts`**

```ts
// src/util/pool.ts
export async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  fn: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let cursor = 0;
  const workers = Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, async () => {
    while (true) {
      const i = cursor++;
      if (i >= items.length) break;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}
```

```ts
// src/util/atomic-write.ts
import { writeFile, rename, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export async function atomicWriteJson(path: string, data: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const tmp = `${path}.tmp`;
  await writeFile(tmp, JSON.stringify(data, null, 2) + '\n', 'utf8');
  await rename(tmp, path);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/pool.test.ts`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/util/pool.ts apps/recipe-pipeline/src/util/atomic-write.ts apps/recipe-pipeline/test/pool.test.ts
git commit -m "feat(recipe-pipeline): concurrency pool + atomic json write"
```

### Task 5.2:管线编排

**Files:**
- Create: `apps/recipe-pipeline/src/pipeline.ts`
- Test: `apps/recipe-pipeline/test/pipeline.test.ts`

- [ ] **Step 1: 写失败测试**(用内存 stub 源 + stub enricher,端到端验证)

```ts
// test/pipeline.test.ts
import { describe, it, expect } from 'vitest';
import { tmpdir } from 'node:os';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { runPipeline } from '../src/pipeline';
import type { RecipeSource, RawRecipe } from '../src/sources/types';
import type { RecipeEnricher } from '../src/clean/enrich';
import type { Enrichment } from '../src/clean/schema';

function source(id: string, recipes: RawRecipe[]): RecipeSource {
  return {
    id, kind: 'deterministic',
    async *collect() { for (const r of recipes) yield r; },
  };
}

const stubEnricher: RecipeEnricher = {
  async enrich(raw): Promise<Enrichment> {
    return {
      category: '荤菜', difficulty: 2, cookingMinutes: 15, description: raw.description ?? '描述',
      ingredients: raw.rawIngredients.map((n) => ({ name: n, quantity: '', unit: '', amount: '' })),
      steps: raw.steps, tags: [],
    };
  },
};

async function setup() {
  const dir = await mkdtemp(join(tmpdir(), 'rp-'));
  const existingPath = join(dir, 'howtocook.json');
  const outPath = existingPath;
  const rejectsPath = join(dir, 'rejects.json');
  return { dir, existingPath, outPath, rejectsPath };
}

const raw = (id: string, name: string): RawRecipe => ({
  id, sourceId: 'howtocook', sourceRef: id, name, sourceCategory: '素菜', sourceDifficulty: 1,
  rawIngredients: ['黄瓜'], steps: ['切'], imageUrl: null,
});

describe('runPipeline', () => {
  it('空既有 -> 全部新增并写盘', async () => {
    const { existingPath, outPath, rejectsPath, dir } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const report = await runPipeline({
      sources: [source('howtocook', [raw('howtocook:vegetable_dish/凉拌黄瓜', '凉拌黄瓜')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z', concurrency: 2,
    });
    expect(report.added).toBe(1);
    const written = JSON.parse(await readFile(outPath, 'utf8'));
    expect(written).toHaveLength(1);
    expect(written[0].category).toBe('素菜');
    void dir;
  });

  it('保住既有 imageUrl', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, JSON.stringify([{
      id: 'howtocook:vegetable_dish/凉拌黄瓜', name: '凉拌黄瓜', category: '素菜', difficulty: 1,
      cookingMinutes: 20, description: '老描述', ingredients: [], steps: [], tags: [],
      imageUrl: 'https://img.jpg', remoteVersion: 5, clientUpdatedAt: null, deletedAt: null,
    }]), 'utf8');
    await runPipeline({
      sources: [source('howtocook', [raw('howtocook:vegetable_dish/凉拌黄瓜', '凉拌黄瓜')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z',
    });
    const written = JSON.parse(await readFile(outPath, 'utf8'));
    expect(written[0].imageUrl).toBe('https://img.jpg');
    expect(written[0].description).toBe('老描述');
    expect(written[0].remoteVersion).toBe(5);
  });

  it('dry-run 不写盘', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const report = await runPipeline({
      sources: [source('howtocook', [raw('howtocook:x/a', 'A')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z', dryRun: true,
    });
    expect(report.added).toBe(1);
    expect(await readFile(outPath, 'utf8')).toBe('[]'); // 未变
  });

  it('enricher 抛错的菜进 rejects 不中断', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const flaky: RecipeEnricher = {
      async enrich(r) {
        if (r.name === '坏菜') throw new Error('boom');
        return stubEnricher.enrich(r);
      },
    };
    const report = await runPipeline({
      sources: [source('s', [raw('howtocook:x/good', '好菜'), raw('howtocook:x/bad', '坏菜')])],
      enricher: flaky, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z',
    });
    expect(report.rejected).toBe(1);
    expect(report.added).toBe(1);
    const rejects = JSON.parse(await readFile(rejectsPath, 'utf8'));
    expect(rejects[0].name).toBe('坏菜');
  });

  it('limit 截断采集', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const report = await runPipeline({
      sources: [source('s', [raw('howtocook:x/a', 'A'), raw('howtocook:x/b', 'B'), raw('howtocook:x/c', 'C')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z', limit: 2,
    });
    expect(report.collected).toBe(2);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/pipeline.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `pipeline.ts`**

```ts
// src/pipeline.ts
import { readFile } from 'node:fs/promises';
import * as v from 'valibot';
import type { RecipeSource, RawRecipe, SourceContext } from './sources/types';
import type { RecipeEnricher } from './clean/enrich';
import { assembleRecipe } from './clean/enrich';
import { CleanRecipeSchema, type CleanRecipe } from './clean/schema';
import { dedupe } from './clean/dedup';
import { mergeWithExisting, type MergeOptions } from './clean/merge';
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
  concurrency?: number;
  limit?: number;
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

  // 1) 采集
  const raws: RawRecipe[] = [];
  for (const src of deps.sources) {
    for await (const r of src.collect(ctx)) {
      raws.push(r);
      if (deps.limit && raws.length >= deps.limit) break;
    }
    if (deps.limit && raws.length >= deps.limit) break;
  }
  log(`collected ${raws.length}`);

  // 2) 清洗 + 组装(并发,逐条隔离)
  const rejects: Reject[] = [];
  const cleanedNullable = await mapWithConcurrency(
    raws,
    deps.concurrency ?? 6,
    async (raw): Promise<CleanRecipe | null> => {
      try {
        const enr = await deps.enricher.enrich(raw);
        const assembled = assembleRecipe(raw, enr);
        return v.parse(CleanRecipeSchema, assembled); // 写前闸门
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

  // 3) 去重
  const { kept, dropped } = dedupe(cleaned);
  log(`deduped: dropped ${dropped.length}`);

  // 4) 合并现有
  const existingRaw = await readFile(deps.existingPath, 'utf8').catch(() => '[]');
  const existing = JSON.parse(existingRaw) as CleanRecipe[];
  const { merged, stats } = mergeWithExisting(kept, existing, deps.now, {
    refreshDescriptions: deps.refreshDescriptions,
  });

  // 5) 写盘(原子;dry-run 跳过)
  if (!deps.dryRun) {
    await atomicWriteJson(deps.outPath, merged);
    if (rejects.length) await atomicWriteJson(deps.rejectsPath, rejects);
  }

  return {
    collected: raws.length, cleaned: cleaned.length, rejected: rejects.length,
    deduped: dropped.length, added: stats.added, updated: stats.updated,
    unchanged: stats.unchanged, total: merged.length,
  };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/pipeline.test.ts`
Expected: PASS(全部)。

- [ ] **Step 5: 全量回归 + typecheck**

Run: `npx vitest run && npx tsc --noEmit`
Expected: 全绿。

- [ ] **Step 6: Commit**

```bash
git add apps/recipe-pipeline/src/pipeline.ts apps/recipe-pipeline/test/pipeline.test.ts
git commit -m "feat(recipe-pipeline): pure pipeline orchestration (collect→clean→dedup→merge→write)"
```

---

## Milestone 6:Flue 集成 + HowToCook 源 + 冒烟

### Task 6.1:HowToCook 采集适配器

**Files:**
- Create: `apps/recipe-pipeline/src/sources/howtocook.ts`
- Test: `apps/recipe-pipeline/test/howtocook-source.test.ts`

- [ ] **Step 1: 写失败测试**(只测纯函数:id 推导 + 单文件 → RawRecipe;克隆/遍历是集成,不单测)

```ts
// test/howtocook-source.test.ts
import { describe, it, expect } from 'vitest';
import { howtocookIdFromPath, rawFromMarkdown } from '../src/sources/howtocook';

describe('howtocookIdFromPath', () => {
  it('直挂文件', () => {
    expect(howtocookIdFromPath('dishes/vegetable_dish/凉拌黄瓜.md'))
      .toBe('howtocook:vegetable_dish/凉拌黄瓜');
  });
  it('子目录文件', () => {
    expect(howtocookIdFromPath('dishes/vegetable_dish/鸡蛋花/鸡蛋花.md'))
      .toBe('howtocook:vegetable_dish/鸡蛋花/鸡蛋花');
  });
});

describe('rawFromMarkdown', () => {
  it('组装 RawRecipe:分类来自目录、难度来自解析', () => {
    const md = '# 凉拌黄瓜的做法\n\n描述。\n\n预估烹饪难度：★\n\n## 必备原料和工具\n\n* 黄瓜\n\n## 操作\n\n1. 切\n';
    const r = rawFromMarkdown('dishes/vegetable_dish/凉拌黄瓜.md', md);
    expect(r.id).toBe('howtocook:vegetable_dish/凉拌黄瓜');
    expect(r.sourceCategory).toBe('素菜');
    expect(r.sourceDifficulty).toBe(1);
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.rawIngredients).toEqual(['黄瓜']);
    expect(r.sourceId).toBe('howtocook');
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/howtocook-source.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `howtocook.ts`**

```ts
// src/sources/howtocook.ts
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, relative, basename } from 'node:path';
import type { RecipeSource, RawRecipe, SourceContext } from './types';
import { parseHowtocook } from '../parse/howtocook-parser';
import { mapHowtocookCategory } from '../parse/category-map';

const exec = promisify(execFile);
const REPO = 'https://github.com/Anduin2017/HowToCook.git';

export function howtocookIdFromPath(relPath: string): string {
  // dishes/<eng>/<...>/<name>.md  ->  howtocook:<eng>/<...>/<name>
  const noPrefix = relPath.replace(/^dishes\//, '').replace(/\.md$/, '');
  return `howtocook:${noPrefix}`;
}

export function rawFromMarkdown(relPath: string, md: string): RawRecipe {
  const parsed = parseHowtocook(md);
  const engCat = relPath.replace(/^dishes\//, '').split('/')[0];
  return {
    id: howtocookIdFromPath(relPath),
    sourceId: 'howtocook',
    sourceRef: relPath,
    name: parsed.name || basename(relPath, '.md'),
    sourceCategory: mapHowtocookCategory(engCat),
    sourceDifficulty: parsed.difficulty,
    description: parsed.description,
    rawIngredients: parsed.rawIngredients,
    portionText: parsed.portionText,
    steps: parsed.steps,
    imageUrl: null,
  };
}

async function* walkMarkdown(dir: string, root: string): AsyncIterable<string> {
  for (const entry of await readdir(dir)) {
    const full = join(dir, entry);
    const s = await stat(full);
    if (s.isDirectory()) yield* walkMarkdown(full, root);
    else if (entry.endsWith('.md') && entry !== 'README.md') yield relative(root, full);
  }
}

export function howtocookSource(): RecipeSource {
  return {
    id: 'howtocook',
    kind: 'deterministic',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      const repoDir = join(ctx.workDir, 'howtocook');
      await exec('git', ['clone', '--depth', '1', REPO, repoDir]).catch(async (e) => {
        ctx.log(`clone skipped/failed (${String(e)}); 假定已存在 ${repoDir}`);
      });
      const dishesDir = join(repoDir, 'dishes');
      for await (const relPath of walkMarkdown(dishesDir, repoDir)) {
        const md = await readFile(join(repoDir, relPath), 'utf8');
        const raw = rawFromMarkdown(relPath, md);
        if (raw.rawIngredients.length || raw.steps.length) yield raw;
      }
    },
  };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/howtocook-source.test.ts`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/sources/howtocook.ts apps/recipe-pipeline/test/howtocook-source.test.ts
git commit -m "feat(recipe-pipeline): howtocook source adapter (clone + walk + parse)"
```

### Task 6.2:配置 + 源注册表

**Files:**
- Create: `apps/recipe-pipeline/src/config.ts`
- Create: `apps/recipe-pipeline/src/sources/registry.ts`
- Create: `apps/recipe-pipeline/data/sources.json`

- [ ] **Step 1: 实现 `config.ts`**

```ts
// src/config.ts
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export const config = {
  // apps/recipe-pipeline -> apps/ios/FreshPantry/Resources/howtocook.json
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  workDir: resolve(root, '.cache'),
  model: process.env.RECIPE_MODEL ?? 'anthropic/claude-sonnet-4-6',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};
```

- [ ] **Step 2: 实现 `data/sources.json`**(首期只启用 howtocook;扩充留位)

```json
{
  "sources": [
    { "type": "howtocook", "enabled": true }
  ]
}
```

- [ ] **Step 3: 实现 `registry.ts`**

```ts
// src/sources/registry.ts
import type { RecipeSource } from './types';
import { howtocookSource } from './howtocook';
import { markdownRepoSource, type MarkdownRepoConfig } from './markdown-repo';
import { urlBatchSource, type UrlBatchConfig } from './url-batch';
import type { RecipeEnricher } from '../clean/enrich';

export type SourceConfig =
  | { type: 'howtocook'; enabled?: boolean }
  | ({ type: 'markdown-repo'; enabled?: boolean } & MarkdownRepoConfig)
  | ({ type: 'url-batch'; enabled?: boolean } & UrlBatchConfig);

export interface SourcesFile {
  sources: SourceConfig[];
}

export function buildSources(file: SourcesFile, enricher: RecipeEnricher): RecipeSource[] {
  return file.sources
    .filter((s) => s.enabled !== false)
    .map((s) => {
      switch (s.type) {
        case 'howtocook':
          return howtocookSource();
        case 'markdown-repo':
          return markdownRepoSource(s);
        case 'url-batch':
          return urlBatchSource(s, enricher);
      }
    });
}
```

> `markdown-repo` 与 `url-batch` 在 Milestone 7 实现;本任务先建 registry 框架,Milestone 7 完成后这两个 import 才解析得了。**执行顺序:先做 Task 7.1/7.2 再回填本文件的两个分支,或本任务先只实现 howtocook 分支、Milestone 7 再补**。推荐后者:Step 3 先只留 howtocook 分支(其余 case 抛 `throw new Error('not implemented')`),Milestone 7 落地后替换。

- [ ] **Step 4: Commit**

```bash
git add apps/recipe-pipeline/src/config.ts apps/recipe-pipeline/src/sources/registry.ts apps/recipe-pipeline/data/sources.json
git commit -m "feat(recipe-pipeline): config + source registry (howtocook enabled)"
```

### Task 6.3:Flue agent + enricher + workflow

**Files:**
- Create: `apps/recipe-pipeline/src/agents/recipe-cleaner.ts`
- Create: `apps/recipe-pipeline/src/clean/flue-enricher.ts`
- Create: `apps/recipe-pipeline/src/workflows/build-recipes.ts`

- [ ] **Step 1: 实现 agent `recipe-cleaner.ts`**

```ts
// src/agents/recipe-cleaner.ts
import { createAgent } from '@flue/runtime';
import { RECIPE_CLEANER_INSTRUCTIONS } from '../clean/enrich';
import { config } from '../config';

export default createAgent(() => ({
  model: config.model,
  instructions: RECIPE_CLEANER_INSTRUCTIONS,
}));
```

- [ ] **Step 2: 实现 `flue-enricher.ts`**(唯一触碰 flue session/result 的文件)

```ts
// src/clean/flue-enricher.ts
import { EnrichmentSchema } from './schema';
import { buildEnrichPrompt, type RecipeEnricher } from './enrich';

// harness 由 workflow 的 init(agent) 提供;此处只用其 session().prompt(..., { result })
interface Harness {
  session(): Promise<{
    prompt(input: string, opts: { result: typeof EnrichmentSchema }): Promise<{ data: unknown }>;
  }>;
}

export function createFlueEnricher(harness: Harness): RecipeEnricher {
  return {
    async enrich(raw) {
      const session = await harness.session();
      const res = await session.prompt(buildEnrichPrompt(raw), { result: EnrichmentSchema });
      return res.data as Awaited<ReturnType<RecipeEnricher['enrich']>>;
    },
  };
}
```

> **实现期核对点**:`harness.session()` / `session.prompt(input, { result })` / `res.data` 的确切签名以 flue SDK 实际类型为准(`@flue/runtime` 的 `FlueContext`/`init` 返回类型)。若类型不符,只改本文件 + workflow 两处,纯核心不受影响。文档依据:agent-api「Pass a Valibot schema as options.result to resolve with validated response.data」+ workflows「init(agent)→harness.session()→session.prompt()」。

- [ ] **Step 3: 实现 workflow `build-recipes.ts`**

```ts
// src/workflows/build-recipes.ts
import { readFile } from 'node:fs/promises';
import type { FlueContext } from '@flue/runtime';
import recipeCleaner from '../agents/recipe-cleaner';
import { createFlueEnricher } from '../clean/flue-enricher';
import { buildSources, type SourcesFile } from '../sources/registry';
import { runPipeline } from '../pipeline';
import { config } from '../config';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

export interface BuildPayload {
  limit?: number;
  dryRun?: boolean;
  refreshDescriptions?: boolean;
}

export async function run({ init, payload }: FlueContext<BuildPayload>) {
  const harness = await init(recipeCleaner);
  const enricher = createFlueEnricher(harness);

  const sourcesPath = resolve(dirname(fileURLToPath(import.meta.url)), '../../data/sources.json');
  const sourcesFile = JSON.parse(await readFile(sourcesPath, 'utf8')) as SourcesFile;
  const sources = buildSources(sourcesFile, enricher);

  const report = await runPipeline({
    sources,
    enricher,
    existingPath: config.existingPath,
    outPath: config.outPath,
    rejectsPath: config.rejectsPath,
    workDir: config.workDir,
    now: new Date().toISOString(),
    concurrency: config.concurrency,
    limit: payload?.limit,
    dryRun: payload?.dryRun,
    refreshDescriptions: payload?.refreshDescriptions,
    log: (m) => console.log(`[recipes] ${m}`),
  });

  console.log('[recipes] report', report);
  return report;
}
```

- [ ] **Step 4: typecheck**

Run: `cd apps/recipe-pipeline && npx tsc --noEmit`
Expected: 通过。若 `FlueContext`/`init` 类型与 `flue-enricher.ts` 的 `Harness` 接口不匹配,按 SDK 实际类型修正这两个文件。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/agents/recipe-cleaner.ts apps/recipe-pipeline/src/clean/flue-enricher.ts apps/recipe-pipeline/src/workflows/build-recipes.ts
git commit -m "feat(recipe-pipeline): flue agent + enricher + build-recipes workflow"
```

### Task 6.4:真实冒烟(env 门控,3 条)

**Files:** 无新文件(手动验证 + 记录)

- [ ] **Step 1: 备好 key**

```bash
cd apps/recipe-pipeline
cp .env.example .env
# 编辑 .env 填入真实 ANTHROPIC_API_KEY
```

- [ ] **Step 2: dry-run 限 3 条冒烟**

Run:
```bash
cd apps/recipe-pipeline && flue run build-recipes --target node --payload '{"dryRun":true,"limit":3}'
```
Expected: 打印 `[recipes] report { collected: 3, cleaned: 3, ... }`;`howtocook.json` 未被改动(dry-run);无报错。

- [ ] **Step 3: 核对清洗质量**

人工抽查 stdout / 临时把 dryRun 改 false 跑 limit:3 后 `git diff apps/ios/FreshPantry/Resources/howtocook.json`:确认这 3 条的 `amount` 有从「计算段」填上、`description` 黏住既有、`category/difficulty` 与目录/★一致。核对后 `git checkout` 回滚这次试写。

- [ ] **Step 4: 若 flue API 与代码不符 —— 修正点清单**

逐一核对并就地修:`init(agent)` 返回值是否有 `.session()`;`session.prompt` 第二参是否 `{ result }`;返回是否 `.data`;`FlueContext` 泛型与 `payload` 取法。只动 `flue-enricher.ts` / `build-recipes.ts`。

- [ ] **Step 5: Commit(若有修正)**

```bash
git add -A apps/recipe-pipeline/src
git commit -m "fix(recipe-pipeline): align flue session/result API with SDK"
```

---

## Milestone 7:可插拔扩充适配器(框架完成)

### Task 7.1:通用 markdown 仓库适配器

**Files:**
- Create: `apps/recipe-pipeline/src/sources/markdown-repo.ts`
- Test: `apps/recipe-pipeline/test/markdown-repo.test.ts`

- [ ] **Step 1: 写失败测试**(纯函数:配置 → id;复用 howtocook-parser)

```ts
// test/markdown-repo.test.ts
import { describe, it, expect } from 'vitest';
import { markdownRepoIdFor, rawFromRepoMarkdown } from '../src/sources/markdown-repo';

const cfg = { name: 'mycookbook', repo: 'https://github.com/x/y.git', dishesDir: 'recipes', category: '荤菜' as const };

describe('markdownRepoIdFor', () => {
  it('repo:<name>:<slug>', () => {
    expect(markdownRepoIdFor(cfg, 'recipes/红烧肉.md')).toBe('repo:mycookbook:红烧肉');
  });
});

describe('rawFromRepoMarkdown', () => {
  it('用配置兜底分类,复用 howtocook 解析', () => {
    const md = '# 红烧肉的做法\n\n预估烹饪难度：★★\n\n## 必备原料和工具\n\n* 五花肉\n\n## 操作\n\n1. 焯水\n';
    const r = rawFromRepoMarkdown(cfg, 'recipes/红烧肉.md', md);
    expect(r.id).toBe('repo:mycookbook:红烧肉');
    expect(r.sourceCategory).toBe('荤菜');
    expect(r.sourceId).toBe('repo:mycookbook');
    expect(r.rawIngredients).toEqual(['五花肉']);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/markdown-repo.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `markdown-repo.ts`**

```ts
// src/sources/markdown-repo.ts
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, relative, basename } from 'node:path';
import type { RecipeSource, RawRecipe, SourceContext } from './types';
import type { Category } from '../clean/schema';
import { parseHowtocook } from '../parse/howtocook-parser';

const exec = promisify(execFile);

export interface MarkdownRepoConfig {
  name: string;
  repo: string;        // git url
  dishesDir: string;   // 仓库内菜谱根目录
  category?: Category; // 整库统一分类兜底(无则交 LLM 归一)
}

export function markdownRepoIdFor(cfg: MarkdownRepoConfig, relPath: string): string {
  const slug = basename(relPath, '.md');
  return `repo:${cfg.name}:${slug}`;
}

export function rawFromRepoMarkdown(cfg: MarkdownRepoConfig, relPath: string, md: string): RawRecipe {
  const parsed = parseHowtocook(md);
  return {
    id: markdownRepoIdFor(cfg, relPath),
    sourceId: `repo:${cfg.name}`,
    sourceRef: relPath,
    name: parsed.name || basename(relPath, '.md'),
    sourceCategory: cfg.category,
    sourceDifficulty: parsed.difficulty,
    description: parsed.description,
    rawIngredients: parsed.rawIngredients,
    portionText: parsed.portionText,
    steps: parsed.steps,
    imageUrl: null,
  };
}

async function* walkMd(dir: string, root: string): AsyncIterable<string> {
  for (const entry of await readdir(dir)) {
    const full = join(dir, entry);
    const s = await stat(full);
    if (s.isDirectory()) yield* walkMd(full, root);
    else if (entry.endsWith('.md') && entry !== 'README.md') yield relative(root, full);
  }
}

export function markdownRepoSource(cfg: MarkdownRepoConfig): RecipeSource {
  return {
    id: `repo:${cfg.name}`,
    kind: 'deterministic',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      const repoDir = join(ctx.workDir, cfg.name);
      await exec('git', ['clone', '--depth', '1', cfg.repo, repoDir]).catch((e) =>
        ctx.log(`clone ${cfg.name} skipped/failed (${String(e)})`),
      );
      const base = join(repoDir, cfg.dishesDir);
      for await (const relPath of walkMd(base, repoDir)) {
        const md = await readFile(join(repoDir, relPath), 'utf8');
        const raw = rawFromRepoMarkdown(cfg, relPath, md);
        if (raw.rawIngredients.length || raw.steps.length) yield raw;
      }
    },
  };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/markdown-repo.test.ts`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/recipe-pipeline/src/sources/markdown-repo.ts apps/recipe-pipeline/test/markdown-repo.test.ts
git commit -m "feat(recipe-pipeline): pluggable markdown-repo source adapter"
```

### Task 7.2:任意 URL 批量适配器(LLM 抽取)

**Files:**
- Create: `apps/recipe-pipeline/src/sources/url-batch.ts`
- Test: `apps/recipe-pipeline/test/url-batch.test.ts`

- [ ] **Step 1: 写失败测试**(纯函数:HTML→正文、id;抓取注入 fetch 便于测)

```ts
// test/url-batch.test.ts
import { describe, it, expect } from 'vitest';
import { urlIdFor, htmlToText, urlBatchSource } from '../src/sources/url-batch';
import type { RecipeEnricher } from '../src/clean/enrich';

const enr: RecipeEnricher = { async enrich() { throw new Error('unused'); } };

describe('urlIdFor', () => {
  it('host+path slug', () => {
    expect(urlIdFor('https://www.douguo.com/recipe/123.html')).toBe('url:douguo.com/recipe/123.html');
  });
});

describe('htmlToText', () => {
  it('剥标签、压空白', () => {
    expect(htmlToText('<h1>番茄炒蛋</h1><p>步骤:<br>1. 打蛋</p>')).toContain('番茄炒蛋');
    expect(htmlToText('<script>x</script><p>正文</p>')).not.toContain('x');
  });
});

describe('urlBatchSource', () => {
  it('注入 fetch,产出带 rawText 的 RawRecipe(llm-extract)', async () => {
    const fakeFetch = async () => ({ text: async () => '<title>番茄炒蛋</title><p>正文内容</p>' }) as unknown as Response;
    const src = urlBatchSource({ urls: ['https://x.com/r/1'], fetchImpl: fakeFetch }, enr);
    expect(src.kind).toBe('llm-extract');
    const out: string[] = [];
    for await (const r of src.collect({ workDir: '.', log: () => {} })) {
      out.push(r.id);
      expect(r.rawText).toContain('正文内容');
      expect(r.name).toBe('番茄炒蛋'); // 来自 <title>
    }
    expect(out).toEqual(['url:x.com/r/1']);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `npx vitest run test/url-batch.test.ts`
Expected: FAIL — 模块不存在。

- [ ] **Step 3: 实现 `url-batch.ts`**

```ts
// src/sources/url-batch.ts
import type { RecipeSource, RawRecipe, SourceContext } from './types';
import type { RecipeEnricher } from '../clean/enrich';

export interface UrlBatchConfig {
  urls: string[];
  fetchImpl?: typeof fetch; // 测试可注入
}

export function urlIdFor(url: string): string {
  const u = new URL(url);
  const host = u.host.replace(/^www\./, '');
  return `url:${host}${u.pathname}`;
}

export function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>(?=)/gi, '\n')
    .replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function titleOf(html: string): string | undefined {
  const m = html.match(/<title>([^<]*)<\/title>/i);
  return m ? m[1].trim() : undefined;
}

// enricher 当前不在 collect 内调用(抽取在 pipeline 的 enrich 阶段统一做);
// 保留入参以备将来需要源内预处理。
export function urlBatchSource(cfg: UrlBatchConfig, _enricher: RecipeEnricher): RecipeSource {
  const doFetch = cfg.fetchImpl ?? fetch;
  return {
    id: 'url',
    kind: 'llm-extract',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      for (const url of cfg.urls) {
        try {
          const res = await doFetch(url);
          const html = await res.text();
          yield {
            id: urlIdFor(url),
            sourceId: 'url',
            sourceRef: url,
            name: titleOf(html) ?? url,
            rawIngredients: [],
            steps: [],
            rawText: htmlToText(html),
            imageUrl: null,
          };
        } catch (e) {
          ctx.log(`fetch failed ${url}: ${String(e)}`);
        }
      }
    },
  };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `npx vitest run test/url-batch.test.ts`
Expected: PASS。

- [ ] **Step 5: 回填 registry 的两个分支**(若 Task 6.2 当时只留了 howtocook)

确认 `src/sources/registry.ts` 的 `markdown-repo` / `url-batch` 分支已正确调用 `markdownRepoSource(s)` / `urlBatchSource(s, enricher)`(见 Task 6.2 代码),`tsc --noEmit` 通过。

- [ ] **Step 6: 全量回归**

Run: `cd apps/recipe-pipeline && npx vitest run && npx tsc --noEmit`
Expected: 全绿。

- [ ] **Step 7: Commit**

```bash
git add apps/recipe-pipeline/src/sources/url-batch.ts apps/recipe-pipeline/test/url-batch.test.ts apps/recipe-pipeline/src/sources/registry.ts
git commit -m "feat(recipe-pipeline): pluggable url-batch source adapter (llm-extract)"
```

---

## Milestone 8:收尾接线

### Task 8.1:monorepo 脚本 + README + 验收

**Files:**
- Modify: `package.json`(root)
- Create: `apps/recipe-pipeline/README.md`

- [ ] **Step 1: root `package.json` 加脚本**

在 root `package.json` 的 `scripts` 增加:
```json
"recipes:test": "cd apps/recipe-pipeline && npm test",
"recipes:build": "cd apps/recipe-pipeline && npm run build:recipes",
"recipes:build:dry": "cd apps/recipe-pipeline && npm run build:recipes:dry"
```
并把 `check` 改为:
```json
"check": "npm run api:test && npm run recipes:test"
```

- [ ] **Step 2: 写 `apps/recipe-pipeline/README.md`**

```markdown
# @fresh-pantry/recipe-pipeline

Flue 菜谱采集清洗管线:多源采集 → LLM 清洗增强 → 去重 → 按 id 合并 → 写回
`apps/ios/FreshPantry/Resources/howtocook.json`。

## 用法
1. `cp .env.example .env` 填 `ANTHROPIC_API_KEY`
2. 预览:`npm run build:recipes:dry`
3. 全量:`npm run build:recipes`
4. 测试:`npm test`

## 扩充来源
编辑 `data/sources.json`,加 `markdown-repo` 或 `url-batch` 条目(见 `src/sources/registry.ts` 的 `SourceConfig`)。

## 合并保护
按 id 合并:既有 imageUrl/remoteVersion/软删保留,description 黏住,用量「只抽不猜」。详见
`docs/superpowers/specs/2026-06-12-recipe-collection-cleaning-pipeline-design.md`。
```

- [ ] **Step 3: iOS 平价验收**

Run:
```bash
cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FreshPantryTests/LocalRecipeRepositoryTests 2>&1 | tail -5
```
> 仅当本机已配 Xcode/模拟器时执行;目的:确认管线产物仍被 iOS 侧 schema 解析。若环境不便,改为人工 `git diff` 抽查 `howtocook.json` 结构未变(字段集/类型一致)。
Expected: 测试通过(或 diff 仅内容变化、结构不变)。

- [ ] **Step 4: 全量回归**

Run: `cd apps/recipe-pipeline && npx vitest run && npx tsc --noEmit`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add package.json apps/recipe-pipeline/README.md
git commit -m "chore(recipe-pipeline): monorepo scripts + readme + acceptance"
```

---

## 自检对照(Self-Review)

**Spec 覆盖:**
- §3 项目布局 → Task 0.1。 §4.1 RawRecipe → 1.2。 §4.2 CleanRecipe/Enrichment(zod→valibot 修正)→ 1.1。 §4.3 三适配器 → 6.1 / 7.1 / 7.2。 §4.4 清洗 agent + 只抽不猜 → 3.1 / 6.3。 §5 workflow 编排 → 5.2 / 6.3。 §6 合并策略表 → 4.2(逐条测)。 §7 成本(limit/dry-run;缓存见下)→ 5.2 / 6.4。 §8 容错(逐条隔离/zod 闸门/原子写)→ 5.1 / 5.2。 §9 测试 → 各 Task 的测试步 + 8.1 验收。
- **已知偏差(实现期修正,均已在文中标注)**:① 结构化校验从 zod 改 **valibot**(flue `options.result` 要求);② agent/workflow 落 `src/agents`、`src/workflows`(flue 约定);③ 新菜 `clientUpdatedAt` 取 **null**(对齐现有 363 条 seed 约定,非 spec 的「运行时刻」,避免 schema 漂移);④ HowToCook 描述/难度可确定性解析,LLM 主要补用量/时长/标签 —— 更省。
- **§7「内容哈希缓存」未单独建 Task**:`description` 黏住 + dry-run 已覆盖主要省钱诉求;哈希缓存属增量优化,列入「后续可选」不阻塞本期交付。执行者如需,可在 pipeline enrich 前加一层「raw 内容 hash 命中既有则跳过 enrich」。

**占位符扫描:** 无 TBD/TODO;flue session API 的不确定性已收敛为 6.3/6.4 的「实现期核对点」并限定影响面在 2 个文件,非占位。

**类型一致性:** `RawRecipe`(含 `id/sourceCategory/sourceDifficulty/description/portionText/rawText`)、`Enrichment`、`CleanRecipe`、`RecipeEnricher.enrich`、`assembleRecipe(raw, enr)`、`mergeWithExisting(fresh, existing, now, opts)`、`runPipeline(deps)`、`dedupe`、各 source 工厂签名 —— 跨 Task 一致。

**范围:** 单一管线子系统,聚焦,无需拆分。
