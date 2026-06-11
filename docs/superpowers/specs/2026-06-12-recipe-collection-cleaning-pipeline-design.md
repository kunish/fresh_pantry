# 菜谱收集 + 清洗管线(Flue)设计

- **日期**:2026-06-12
- **状态**:已批准设计,待出实施计划
- **落点**:`apps/recipe-pipeline/`(新建,自包含,不动现有 `apps/api`)
- **形态**:Flue(TypeScript)项目,target=node,本地/CI 批处理
- **产物**:写回 `apps/ios/FreshPantry/Resources/howtocook.json`

## 1. 背景与目标

iOS app 的菜谱来自 HowToCook GitHub 仓库的 markdown,过去由一个 Dart 工具(`tool/import_howtocook.dart` + markdown 解析器,commit `e3756a9`/`3e15dbf`)采集清洗生成。SwiftUI 重写后整个 `tool/` 被删除,采集能力丢失。

现状产物 `howtocook.json`:**363 条**,schema 为
`id / name / category / difficulty / cookingMinutes / description / ingredients[] / steps[] / tags[] / imageUrl / remoteVersion / clientUpdatedAt / deletedAt`。
已知缺口:**食材用量全空**(`amount` 0/3102),`description` 为 AI 润色文本,174/363 有 `imageUrl`。

**目标**:用 Flue + LLM 重建采集清洗管线(取代丢失的 Dart 工具),并支持**多源扩充**。本设计采用**分层方案 C**:规整 markdown 仓库走确定性解析,结构未知的任意 URL 走 LLM 抽取,清洗增强(补用量/描述/归一/去重)两条路共用。

**范围决策(已与用户拍板)**:
- 目标形态:复刻 + 扩充语料(不走 LLM 凭空生成新菜)。
- 扩充来源:可插拔 source 框架(首期重点)+ 其他开源中文菜谱仓库 + 任意 URL 批量。
- 清洗职责:结构化+归一(基线)+ 补全食材用量 + 润色/生成 description + 跨源去重。

**非目标**:不改 iOS app 的菜谱 schema;不做 LLM 凭空生成菜谱;不接入 TheMealDB 等外部 API(此前已移除,corpus 维持中文家常方向);具体扩充的仓库清单/URL 清单作为配置后续喂入,本期只交付框架 + HowToCook 跑通。

## 2. 架构总览

```
采集(可插拔 source)──► RawRecipe ──► 清洗增强(LLM agent)──► CleanRecipe
                                          │
                                          ▼
                                   去重 ──► 按 id 合并现有 json ──► 原子写盘
```

采集层与清洗层解耦:任何 source 只产出统一的 `RawRecipe`,下游清洗/去重/合并对来源无感知。

## 3. 项目布局

```
apps/recipe-pipeline/
  flue.config.ts            # flue init 生成(target: node)
  package.json              # @flue/runtime + @flue/cli + 解析依赖
  tsconfig.json
  .env                      # ANTHROPIC_API_KEY(.gitignore)
  agents/
    recipe-cleaner.ts       # createAgent:结构化输出的「清洗增强」agent
  src/
    sources/
      types.ts              # RecipeSource 接口 + RawRecipe 类型
      howtocook.ts          # Tier1 确定性:HowToCook git markdown
      markdown-repo.ts      # Tier1 确定性:通用中文菜谱 markdown 仓库
      url-batch.ts          # Tier2 LLM 优先:任意 URL 抓页 → 交 agent
      registry.ts           # 配置驱动的 source 注册表
    parse/
      howtocook-parser.ts   # 确定性 md → RawRecipe(食材先剥离再判定、步骤去内联 md)
      category-map.ts       # 英文目录名 → 中文 10 分类
    clean/
      schema.ts             # CleanRecipe = howtocook.json 单条 schema(zod)
      enrich.ts             # 调 recipe-cleaner:补用量/描述/归一
      dedup.ts              # 跨源去重
      merge.ts              # 按 id 与现有 json 合并(保 imageUrl/remoteVersion/…)
    pipeline.ts             # flue workflow:collect→clean→dedup→merge→write
    config.ts               # 源清单、模型、路径、限流
  data/
    sources.json            # 配置:要跑哪些仓库/URL(可后续追加)
  test/*.test.ts            # vitest(对齐 apps/api)
```

约定:自包含工程(独立 package.json / node_modules),与现有 `apps/api` 一致;root 非 workspace。

## 4. 接口契约

### 4.1 统一中间态 `RawRecipe`

```ts
interface RawRecipe {
  sourceId: string         // "howtocook" | "repo:<name>" | "url"
  sourceRef: string        // 文件路径或 URL —— 溯源 + 推导 id
  name: string
  sourceCategory?: string  // 源自带分类(英文目录名/原站分类),供归一参考
  rawIngredients: string[] // 食材原始行(可能含用量文本)
  steps: string[]          // 已去内联 markdown 的步骤
  rawText?: string         // 仅 Tier2 URL:整页正文,交 LLM 抽取
  imageUrl?: string | null
}

interface RecipeSource {
  id: string
  kind: 'deterministic' | 'llm-extract'
  collect(ctx: SourceContext): AsyncIterable<RawRecipe>   // 流式产出,内存友好
}
```

### 4.2 输出契约 `CleanRecipe`(zod,与 howtocook.json 单条对齐)

```ts
const CATEGORIES = ['主食','半成品','早餐','水产','汤羹','甜品','素菜','荤菜','酱料','饮品'] as const

const CleanRecipe = z.object({
  id: z.string(),
  name: z.string().min(1),
  category: z.enum(CATEGORIES),
  difficulty: z.number().int().min(1).max(5),
  cookingMinutes: z.number().int().positive(),
  description: z.string(),
  ingredients: z.array(z.object({
    name: z.string().min(1),
    quantity: z.string(),   // 既有数据均为字符串(含空串)
    unit: z.string(),
    amount: z.string(),
  })),
  steps: z.array(z.string()),
  tags: z.array(z.string()),
  imageUrl: z.string().nullable(),
  remoteVersion: z.number().int().default(0),
  clientUpdatedAt: z.string().nullable(),
  deletedAt: z.string().nullable(),
})
```

字段顺序与既有 json 对齐,保证写盘后 diff 干净。

### 4.3 三个采集适配器

- **`howtocook.ts`(确定性)**:浅克隆 HowToCook 仓库 → 遍历 `dishes/<英文类>/<名>/*.md` → `howtocook-parser` 抽食材/步骤,英文目录经 `category-map` 给出 `sourceCategory`。id = `howtocook:<英文类>/<相对路径名>`(沿用既有 id 方案,保证与现有 363 条对齐)。
- **`markdown-repo.ts`(确定性)**:同结构的其他中文菜谱仓库,配置 glob + 字段规则复用 parser。id = `repo:<name>:<slug>`。
- **`url-batch.ts`(LLM 优先)**:抓页取正文塞进 `rawText`,`name` 兜底用 `<title>`,其余字段留给 agent。id = `url:<slug(host+path)>`。

### 4.4 清洗 agent `recipe-cleaner`

`createAgent` + 结构化输出(zod 校验),只产出「LLM 该管的字段」:

```ts
{ category,           // 归一到 10 类
  difficulty,         // 1-5
  cookingMinutes,
  description,        // 润色/生成
  ingredients: [{ name, quantity, unit, amount }],  // 补用量
  tags: string[] }
```

- **两种输入形态、同一个 agent**:Tier1 传已解析的 `rawIngredients/steps`(只做增强);Tier2 传 `rawText`(抽取 + 增强一次完成)。
- **补用量「只抽不猜」(食安/准确性护栏)**:指令明确 —— `quantity/unit/amount` 仅当源文本写了才填,源未写一律留空,**禁止 LLM 估算/编造**。
- 确定性字段 `id / name / steps / imageUrl` 由 parser 拥有,不交 LLM 改(URL 源例外:`name/steps` 由 agent 抽)。
- 模型默认 `anthropic/claude-sonnet-4-6`,可配置切 `anthropic/claude-haiku-4-5` 做批量结构化降本。

## 5. Workflow 编排(`pipeline.ts`)

1. **加载配置** → 启用的 sources、现有 `howtocook.json` 路径、模型、并发上限、缓存路径。
2. **采集** → 各 source `collect()` 流式产出 `RawRecipe`。
3. **清洗** → 每条调 `recipe-cleaner`(Tier1 增强 / Tier2 抽取+增强),**并发限流(默认 6)**;逐条 zod 校验;失败重试 1 次,仍失败进 `rejects.json`,不污染产物。
4. **定 id** → 见 4.3,稳定可复现。
5. **跨源去重** → key = 规范化名(去空白/全半角/标点)+ 食材集 Jaccard ≥ 0.6 判重;**规范优先级 HowToCook > 其他仓库 > URL**,留高优先者,丢弃项记日志。
6. **按 id 合并现有 json**(策略见 §6)。
7. **写盘** → 稳定排序、字段顺序对齐既有格式 + 一份 run 报告(采集/清洗/去重/新增/更新/拒绝 计数)。

## 6. 合并策略(对已上线 363 条的保护 —— 最关键)

按 `id` 与现有 `howtocook.json` 合并:

| 字段 | 策略 |
|---|---|
| `imageUrl` | **既有优先**:`existing.imageUrl ?? pipeline.imageUrl` —— 保住已策展的 174 张图 |
| `ingredients[].amount/unit/quantity` | **回填**:这正是目的(现 0/3102 全空),按「只抽不猜」填 |
| `description` | **黏住**:既有非空则保留,仅新增/缺失时生成(除非显式 `--refresh-descriptions`)—— 让重跑稳定、省钱 |
| `remoteVersion` | **保留既有**,新菜 = 0(是否因内容变更 bump 留作开关,默认不动,避免乱了 app 同步) |
| `clientUpdatedAt` | 既有保留;新菜 = 运行时刻 |
| `deletedAt` | 既有保留;**不复活**已软删的菜 |

**幂等性**:同样的源 + 同样的现有 json 重跑 → 无虚假 diff(id 稳定、排序稳定、`description` 黏住;唯一非确定来源是 LLM 文本,已通过「黏住」隔离)。

## 7. 成本控制

- 确定性优先 → 多数字段免费,LLM 只做 enrichment;`description` 黏住 → 重跑不再为既有 363 条付费。
- **内容哈希缓存**:`RawRecipe` 内容 hash 命中且已在产物中 → 跳过 enrich,增量跑近乎零成本。
- 模型可配:默认 `claude-sonnet-4-6`,批量结构化可切 `claude-haiku-4-5`。
- 开发期开关:`--source X`、`--limit N`、`--dry-run`(只预览 diff + 计数,不写盘)。

## 8. 容错

- **逐条隔离**:单条坏菜 → 进 `rejects.json`,管线继续,绝不整体中断。
- **写前 zod 闸门**:分类不在 10 枚举 / 难度越界 → 纠错重试 1 次,仍错则拒收。
- 采集网络失败 → 退避重试;HowToCook 浅克隆整体失败 → 该 source 快速失败。
- **原子写盘**:先写临时文件再 rename,绝不半写 `howtocook.json`(git 是兜底快照)。

## 9. 测试(vitest,对齐 apps/api;CI 内不打真实 LLM)

- `howtocook-parser`:fixture md → 预期 `RawRecipe`(食材先剥离再判定、步骤去内联 md)golden 测试。
- `category-map`:英文 → 中文 10 类全覆盖。
- `dedup`:构造重复对 → 合并正确、优先级生效。
- **`merge`(最高价值)**:既有记录 + 管线记录 → 逐条验 §6 合并策略表(imageUrl 保留、description 黏住、amount 回填、deletedAt 不复活、remoteVersion 不动)。
- `schema`:zod 接受真实 howtocook.json 记录、拒坏分类/难度。
- `enrich`:**stub 模型**测输入塑形 + 输出合并逻辑;真实 API 只在手动集成 smoke(`--limit 3 --source howtocook`,env 门控)。
- **验收**:HowToCook 全量重跑产物仍能被 iOS 侧 `LocalRecipeRepositoryTests` schema 解析(平价不破)。

## 10. 待实现期确认的开放点

- Flue `workflow` 的确切 API(从 `flueframework.com/docs/guide/workflows/` 与 `/docs/api/` 核对;若 workflow 抽象不契合批处理,退化为 `flue` 调用的 node 入口脚本编排,agent 仍用 `createAgent`)。
- Flue 结构化输出/工具调用的确切写法(从 SDK 文档核对 zod 集成方式)。
- 单测如何 stub flue 的 model(查 flue 测试支持;无则抽象 enrich 的 model 调用为可注入依赖)。
