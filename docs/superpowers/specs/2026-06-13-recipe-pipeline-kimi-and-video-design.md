# recipe-pipeline:换 Kimi 模型 + 菜谱视频搜集补齐 + 全量重跑

- 日期:2026-06-13
- 状态:已批准设计,待实现
- 范围:`apps/recipe-pipeline/`(管线)+ `apps/ios/`(消费端 + DB 种子)

## 背景

`apps/recipe-pipeline/` 是 Flue 菜谱采集清洗管线:多源采集 → LLM 清洗增强(`RecipeEnricher`
seam)→ 去重 → 按 id 合并 → 写回 `apps/ios/FreshPantry/Resources/howtocook.json` + 生成
Supabase `public.recipes` 种子迁移。当前 364 条已全量清洗 + 零缺图(封面托管 Supabase Storage)。
LLM 默认走 `anthropic/claude-sonnet-4-6`(或 opencode zen 的 `deepseek-v4-pro`)。

本次三件事:
1. **换模型**:管线 enrich 改走 Cloudflare Workers AI 渠道的 `@cf/moonshotai/kimi-k2.7-code`。
2. **新增菜谱视频**:为每道菜搜集一条「做法视频」外链并补齐,iOS 端到端可看。
3. **全量重跑**:用新模型把 364 条全部重新清洗,并补齐视频。

### Cloudflare 渠道(已实测)

- Base URL(OpenAI 兼容):`https://api.cloudflare.com/client/v4/accounts/3967805080c0f0812c8e59d1f9c699a6/ai/v1`
- Key:`cfut_…`(`cfut_` 前缀的 Workers AI 用户 token,`Authorization: Bearer`)。
- 模型 id:`@cf/moonshotai/kimi-k2.7-code`(用户原串 `@cf/moonshotai/kimi-@cf/moonshotai/kimi-k2.7-code`
  是粘贴重复,已用 `ai/models/search` 核实真实 id;账户内同时有 `kimi-k2.6`)。
- **结构化输出可用**:`response_format: json_schema`(实测返回合法
  `{"category":"素菜","difficulty":1}`,`finish:stop`),tool-calling 亦可。
- **运营注意**:① 偶发 `Capacity temporarily exceeded`(`code 3040`,瞬时限流)→ 必须重试退避;
  ② 推理模型,小输出也烧近 200 completion tokens → `max_tokens` 要给足。

凭据放 `.env`,**绝不入库**(沿用现有 `.env` 约定)。

## A. 模型替换 — 直连 enricher(藏在 `RecipeEnricher` seam 后)

不走 flue 原生 provider 注册(容量重试不可控、依赖 Pi 的 CF token 约定、`thinkingLevel` 被忽略、
`flue run` 下注册入口不确定)。改为新增 `CloudflareEnricher` 实现现有 `RecipeEnricher` 接口:

- `src/clean/cloudflare-enricher.ts`:`createCloudflareEnricher(opts)` 返回 `RecipeEnricher`。
  - 直接 `fetch` `${baseUrl}/chat/completions`,messages = `[{role:'system', content:
    RECIPE_CLEANER_INSTRUCTIONS}, {role:'user', content: buildEnrichPrompt(raw)}]`。
  - `response_format: { type:'json_schema', json_schema:{ name:'enrichment', schema: <派生自
    EnrichmentSchema> } }`,`strict:false`(避开 OpenAI strict 模式对 optional 的限制;
    最终正确性由管线既有 `v.parse(CleanRecipeSchema, …)` + 质量闸门保证)。
  - schema 派生:用 `@valibot/to-json-schema`(已在依赖树,提为直接 devDep/dep)把
    `EnrichmentSchema` 转 JSON Schema;转换在模块加载时算一次。
  - **重试退避**:对 `code 3040` / HTTP 429 / 5xx / 网络错指数退避重试(默认 5 次,
    base 1s,封顶 ~30s,带抖动);对「返回 200 但 body 带 `errors`」也识别为可重试。
  - `max_tokens` 默认充足(如 4096),可 env 覆盖。
  - 解析 `choices[0].message.content` → `JSON.parse` → 返回(管线后续 `v.parse` 兜底);
    JSON.parse 失败则**重提一次**(prompt 末尾追加「只回 JSON、不要解释」),再失败抛错
    → 该条进 `rejects.json`(沿用现有失败语义)。
  - 全部网络/时间通过参数注入(`fetchImpl`、`sleep`),**可全单测**。
- `src/config.ts`:加 `cloudflare` 凭据读取——`CLOUDFLARE_AI_BASE_URL`(默认即上方账户的
  `/ai/v1` base)+ `CLOUDFLARE_AI_API_KEY`。enricher 选择**单一判据**:`RECIPE_MODEL` 以
  `@cf/` 开头 → `CloudflareEnricher`,否则走 flue 路径。默认 `RECIPE_MODEL=@cf/moonshotai/kimi-k2.7-code`。
- `src/workflows/build-recipes.ts`:按 config 选 enricher;选 Cloudflare 时不再需要 flue harness。
- `.env.example` / `README.md`:补 Cloudflare 渠道用法。

向后兼容:Anthropic / DeepSeek 路径保留,不删 `createFlueEnricher`。

## B. 菜谱视频:外链 URL + 出处可溯源

### 数据形态

- `clean/schema.ts`:`CleanRecipeSchema` 加 `videoUrl: v.nullable(v.string())`(镜像
  `imageUrl`;**不进 `EnrichmentSchema`**——视频不由 LLM enrich 产出,与 `imageUrl` 同属
  assemble/merge 维度)。
- `assembleRecipe`:`videoUrl` 初始 `null`。
- `merge`:`videoUrl` 既有优先(不覆盖),除非新增 `refreshVideos` 选项;含义对齐 `imageUrl` 保护。
- 出处落 `data/video-attributions.json`:`{ id, videoUrl, sourcePage, title, provider, confidence }`,
  可溯源、可替换。

### 采集(ultracode workflow)

- `data/acquired-videos/acquire-videos.workflow.mjs`(镜像 `data/acquired/acquire-images.workflow.mjs`):
  每道菜一个 Claude agent →
  - WebSearch「<菜名> 做法 视频」/「<菜名> 教程」/「<name> recipe video」;
  - 优先 B站(bilibili.com)/ YouTube / 下厨房(xiachufang.com)等可信来源;
  - WebFetch 候选页校验「该视频确为这道菜」(标题/简介/up 主匹配),择优;
  - 返回 `{ index, id, ok, videoUrl, sourcePage, title, provider, confidence, reason }`(StructuredOutput schema);
  - 写 `data/acquired-videos/<i>.json`。
  - 支持 `{indices:[…]}` / `{start,end}` 子集补跑;`log` 出未匹配数(no silent caps)。
- `_dishes.json` 复用 / 重生成:给每个 agent 喂 `{i,id,name,category,ings}`(沿用补图的 `_dishes.json` 思路)。

### 回写

- `src/clean/fetch-videos.ts`:纯函数 `applyAcquiredVideos(recipes, acquired)` →
  把 `videoUrl` 回写进 recipes(既有优先),返回新数组 + 命中数;`mergeVideoAttributions`
  合并出处(镜像 `applyAcquiredImages` / `mergeAttributions`,**有单测**)。
- `src/db/apply-web-videos.ts`(`npm run videos:apply`):聚合 `data/acquired-videos/*.json` →
  `applyAcquiredVideos` → 原子写回 `howtocook.json` + 合并 `data/video-attributions.json`。

> 为什么视频搜集用 Claude workflow 而非 Kimi:搜集要 WebSearch/WebFetch 找+验真实 URL,
> Kimi API 这里没联网工具;补图已用此模式跑通 187 条。Kimi 只负责文本 enrich。

## C. 全量重清洗(用户选「全量重清洗 + 补视频」)

- `npm run build:recipes`,`payload`:`{ "skipImages": true, "refreshDescriptions": true }`,
  enricher = Kimi。`skipImages:true` 护住已迁 Storage 的 `imageUrl`(对齐用量回填轮的做法)。
- 回归风险缓解(顺序内置):
  1. 先 `flue run build-recipes --payload '{"limit":5,"dryRun":true,"skipImages":true}'` 给用户看 Kimi 小样质量;
  2. `howtocook.json` 已 git 提交 = 天然备份,跑前确认工作区干净;
  3. 质量闸门自动把坏条目 reject 进 `data/rejects.json`,跑后核查 rejects 数;
  4. `gen:seed` / 灌 DB 前 `git diff` 抽检关键字段(分类/步骤/用量未异常漂移)。

## D. iOS 端到端 + DB

- DB(`src/db/recipe-sql.ts`):`COLUMNS` 加 `video_url`;`RECIPES_DDL` 末尾加
  `alter table public.recipes add column if not exists video_url text;`(幂等,老库可升级);
  `valuesRow` 加 `nullableText(r.videoUrl)`;`CatalogRecipe` 加 `videoUrl`。`gen:seed` 重生成迁移。
- iOS `Recipe.swift`:加 `var videoUrl: String?`;`CodingKeys` 加 `videoUrl`;`init` 形参 +
  `copyWith` + `encode`(`encodeAlways` 对齐 `imageUrl`)+ `decode`(`decodeLenientIfPresent`,
  缺字段向后兼容 nil)。
- iOS `RemoteRecipeCatalog.swift`:第 39 行 select 串末尾加 `,videoUrl:video_url`。
- iOS `RecipeDetailView.swift`:`videoUrl != nil` 时显示「观看视频」入口 →
  `SFSafariViewController`(`SafariView` 包装,`UIViewControllerRepresentable`)打开外链。
- 自建用户菜谱(custom recipes,非 catalog)不涉及视频。

## 执行顺序

1. **模型替换(A)** + 小样验证(`--limit 5 --dryRun`,给用户看质量)。
2. **video 落地(D + B 的 schema/回写侧)**:schema/assemble/merge `videoUrl`、DB 列、iOS 模型/catalog/详情页 UI。
3. **全量重清洗(C)**:Kimi 重跑 364(`skipImages:true,refreshDescriptions:true`)。
4. **视频采集(B)**:workflow 跑 364 → `videos:apply` 回写。
5. **gen:seed + 灌 DB + `git diff` 抽检**。
6. **测试全绿 + iOS 编译**。

> 顺序要点:schema 的 `videoUrl` 必须在「全量重清洗」写盘前就位(否则 `v.parse(CleanRecipeSchema)`
> 失败)。重清洗在前(只改文本、`videoUrl` 维持 null),视频 apply 在后(只填 `videoUrl`),互不打架。

## 测试

- `CloudflareEnricher` 单测(注入 fetch/sleep):容量错重试→成功、429/5xx 重试、JSON 解析失败→重提、
  schema 派生正确、`v.parse` 兜底。
- `recipe-sql` 测:`video_url` 入 `COLUMNS`/DDL/valuesRow,空值 → `null`,有值 → 转义字面量。
- `applyAcquiredVideos` / `mergeVideoAttributions` 纯函数单测(既有优先、合并去重)。
- iOS `Recipe` decode 测:含 `videoUrl`、缺 `videoUrl`(向后兼容 nil)、encode 往返。

## 非目标(YAGNI)

- 不下载/不托管视频本体(仅外链 URL);不抓视频缩略图(本轮);
- 不给自建用户菜谱加视频;不做应用内原生播放器(用 `SFSafariViewController` 打开);
- 不动既有封面 / Storage 流程;不删 flue / Anthropic / DeepSeek enricher 路径。
