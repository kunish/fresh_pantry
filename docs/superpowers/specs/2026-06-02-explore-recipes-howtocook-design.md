# 探索 tab 换用 HowToCook 本地中文食谱库 — 设计

- 日期：2026-06-02
- 状态：已与维护者确认方向，待评审 spec 后转实现计划
- 关联：替换 `docs/superpowers/plans/2026-04-08-open-api-data-enrichment.md`（TheMealDB 接入）在探索 tab 的数据来源职责

## 1. 背景与根因

探索 tab（`recipes_screen.dart` 的 `_RecipeTab.explore`）的食谱全是英文。根因不是 UI 文案，而是数据源：

```
recipesFetchProvider（取库存前 3 个食材 → FoodKnowledge.englishName 翻成英文词）
  → recipeSearchRepository.searchByName(英文词)
    → MealDbApi.searchByName → TheMealDB（https://www.themealdb.com，纯英文、基本是西餐）
```

因此问题有两层：**语言是英文**，且**菜系是西餐**，与中文食材/口味不合。

调研结论（2026-06-02）：

- 主流中文菜谱 API（聚合数据、天行、极速）共性是需注册 + 实名 + appkey、免费额度有限，且**只支持按菜名/分类查询，无「按食材反查菜谱」端点**。换用后，探索 tab 「用库存食材推荐能做的菜」这一核心交互会退化成普通菜名搜索框。
- 开源中文食谱数据集 [HowToCook](https://github.com/Anduin2017/HowToCook)：**Unlicense（公共领域）**、数百道家常中餐、Markdown 结构化（食材表 + 步骤、分荤素/水产/主食/汤粥等）。食材名为中文，与库存中文名可直接做匹配，能复用现有匹配逻辑并保住核心交互。

维护者已确认采用 HowToCook 本地库方案。

## 2. 目标 / 非目标

目标：

- 探索 tab 数据源从 TheMealDB（远程/英文/西餐）换成 HowToCook（本地/中文/家常菜）。
- 保住核心交互：用库存食材推荐能做的菜，复用 `matchedIngredientCountForNames` / `recipeIngredientMatchesInventory`，不再经英文翻译。
- 离线、零 key、零网络依赖。

非目标（YAGNI）：

- 不保留 TheMealDB 并存，不做 AI 翻译兜底。
- 不打包菜品图片（控制 app 体积）。
- 不动 `Recipe` 模型、recipe_card UI、「我的/自定义食谱」、收藏、时间筛选 UI。
- 不对 `FoodKnowledge` 做大改（其它用途保留；仅探索 tab 不再调用 `englishName`）。

## 3. 数据来源与许可

- 来源：HowToCook 仓库 `dishes/**/*.md`。
- 许可：Unlicense（公共领域），可自由使用、修改、再分发。
- 仓库内目录是混合结构：部分为 `菜名.md`，部分为 `菜名/菜名.md`（子目录含图片 + md）。预处理需递归扫描所有 `.md`，并跳过非菜谱文件（如 README、模板）。

HowToCook 单篇 markdown 的实际结构（以「可乐鸡翅」为样例）：

```markdown
# 可乐鸡翅的做法

可乐鸡翅色泽红亮……从备料到完成大约耗时 40 分钟。

预估烹饪难度：★★★

预估卡路里：960 大卡

## 必备原料和工具

* 鸡翅中
* 可乐
...

## 计算

按照 1 盘的份量：

* 鸡翅 10 ～ 12 只
* 可乐 500ml
...

## 操作

1. 鸡翅入锅……
2. ……

## 附加内容

* ……
```

## 4. 预处理脚本设计（离线一次性）

- 脚本：`tool/import_howtocook.dart`，入参为本地 HowToCook clone 的路径（维护者先 `git clone` 一份），避免脚本内嵌网络逻辑。
- 行为：递归扫 `dishes/**/*.md` → 逐篇解析为 `Recipe` → 序列化为 `assets/recipes/howtocook.json`（`List<Recipe>.toJson()` 的数组）。
- 产物与脚本提交进仓库；**不**把上游几百个 md 提交进来。脚本头部记录数据来源仓库与所采用的 commit，便于将来重跑更新。
- 体积预期：纯文本、无图，数百道菜约几百 KB ~ 1MB，可接受。
- app 运行时只读该 asset，需在 `pubspec.yaml` 注册 `assets/recipes/`。

解析要点：

- 跳过文件：文件名/标题不含「的做法」且无 `## 操作` 段者视为非菜谱，跳过。
- 容错：任一段缺失时按下文 gap 策略降级，不让单篇解析失败中断整体导入；导入结束打印「成功 N 篇 / 跳过 M 篇」统计，便于人工核对，不静默吞掉异常篇目。

## 5. 运行时架构（最小侵入）

```
旧:  recipesFetchProvider(库存前3→英文词) → recipeSearchRepository.searchByName → TheMealDB(HTTP)
新:  localRecipesProvider(读 asset json，一次性缓存) ──┐
     recipesFetchProvider(改:不再翻译/联网) ───────────┴→ 按库存食材中文匹配 → 排序
```

- 新增 `LocalRecipeRepository`：从 `howtocook.json` 加载 `List<Recipe>`；提供「全部」与「按菜名/食材过滤」查询。通过 `rootBundle`（或注入的 asset 读取接口）加载，便于测试时注入假数据。
- 新增 `localRecipesProvider`（`FutureProvider<List<Recipe>>`，加载一次并缓存）。
- 改 `recipesFetchProvider`：数据来源切到本地库，删除 `FoodKnowledge.englishName` 翻译那段；保留「取库存食材 → 匹配 → 排序」骨架，匹配直接用中文。
- 探索 tab 搜索框（`_query`）：改为本地按菜名/食材过滤，不再联网搜。
- 弃用并删除 TheMealDB 调用链：`services/themealdb_service.dart`、`RecipeSearchRepository` 的网络/缓存部分及其 provider 接线。`Recipe` 模型保留不动；顺带清理 `recipeDetailsCache` 的遗留存储键，避免死数据残留。

下游不变：`recommendedRecipesProvider`、recipe_card、时间筛选、收藏均消费 `Recipe`，对数据来源透明。

## 6. 字段映射

| Recipe 字段 | 来源 | 处理 |
|---|---|---|
| id | 文件相对路径 | 稳定派生（如路径 slug 或哈希），保证跨次导入一致，避免收藏/缓存失效 |
| name | `# X的做法` | 去掉结尾「的做法」 |
| category | 上级目录名 | `meat_dish→荤菜`、`vegetable_dish→素菜`、`aquatic→水产`、`breakfast→早餐`、`staple→主食`、`soup→汤羹`、`dessert→甜品`、`drink→饮品`、`condiment→酱料` 等映射表；未知目录归「其他」 |
| difficulty | `预估烹饪难度：★★★` | 数 ★，clamp 到 1–5 |
| description | 首段正文 | 直接取 |
| ingredients | `## 计算` 段列表 | 正则拆「名 + 分量」（如「鸡翅 10 ～ 12 只」→ name=鸡翅、amount=10～12只）；拆不出分量则全部进 name、amount 空 |
| steps | `## 操作` 段有序列表 | 取顶层有序项；嵌套子贴士合并进所属步骤或忽略 |
| cookingMinutes | 见 Gap ① | 估算 |
| tags | 分类/难度派生 | 可选，先放分类名 |
| imageUrl | 见 Gap ③ | null |

选用 `## 计算` 段而非 `## 必备原料和工具` 段作为食材来源，因前者带分量，信息更全；后者可能含工具项。

## 7. 已知 gap 与处理

- **Gap ①（时长缺结构化数据）**：HowToCook 无统一时长字段。策略：先用正则从描述抽「X 分钟」（如可乐鸡翅的「40 分钟」）；抽不到则按难度兜底估算（★→15、★★→25、★★★→40、★★★★→60、★★★★★→90）。这与现状 TheMealDB 按难度估时长同一思路，时间筛选（≤15/≤30）行为保持可用。
- **Gap ②（食材名带修饰）**：如「鸡翅中」vs 库存「鸡翅」。现有 `recipeIngredientMatchesInventory` 的 `contains` 双向匹配已能覆盖此类（「鸡翅」⊂「鸡翅中」）。先不做额外归一化（量词/部位剥离），留作后续按实际命中率再评估。
- **Gap ③（无图）**：`imageUrl=null`。实现时确认 recipe_card 在无图时优雅降级（占位/纯文本卡片）；TheMealDB 结果本就可能无图，应已支持，需验证。

## 8. 测试策略

- 解析单测：以「可乐鸡翅」等真实样例为 fixture（放 `test/fixtures/`），断言菜名去「的做法」、难度数 ★、`## 计算` 段食材拆分、步骤提取、时长估算（含描述抽取与难度兜底两条路径）正确。
- 边界单测：缺 `## 计算` 段、缺难度、混合目录结构、非菜谱文件跳过。
- `LocalRecipeRepository` 单测：asset 加载 + 按食材匹配 + 按菜名/食材搜索过滤。
- 探索 tab widget 测试：以注入的本地假数据替换原 TheMealDB mock，验证列表渲染、库存匹配排序、搜索过滤、时间筛选。
- 遵循仓库约定：只 `dart format` 本次改动涉及的文件，避免无关重排。

## 9. 合规与致谢

- 在设置/关于页加一行致谢：「食谱数据来自 HowToCook 项目（Unlicense）」并附仓库链接。Unlicense 不强制署名，但作为开源致谢加上。

## 10. 风险与回滚

- 风险：上游 markdown 个别篇排版不规范导致解析降级（分量缺失/步骤合并不理想）。缓解：导入统计 + 单测覆盖边界 + 解析失败篇目可见（不静默跳过）。
- 风险：内置库为静态快照，不会自动更新。可接受（自用 A-mode，重跑脚本即可刷新）。
- 回滚：改动集中在数据源层（新增 provider/repository + 改 `recipesFetchProvider` + 删 TheMealDB 链 + 加 asset）。如需回退，恢复 TheMealDB 接线即可，`Recipe` 模型与下游不受影响。

## 11. 影响的文件（预估）

- 新增：`tool/import_howtocook.dart`、`assets/recipes/howtocook.json`、`lib/storage/local_recipe_repository.dart`、`lib/providers/` 中的 `localRecipesProvider`、相关测试与 fixture。
- 修改：`lib/providers/recipe_provider.dart`（数据源切换、去英文翻译）、`lib/screens/recipes_screen.dart`（搜索改本地过滤）、`pubspec.yaml`（注册 asset）、设置/关于页（致谢）。
- 删除/弃用：`lib/services/themealdb_service.dart` 及 `RecipeSearchRepository` 网络部分与其 provider 接线。
