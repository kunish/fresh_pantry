# @fresh-pantry/recipe-pipeline

Flue 菜谱采集清洗管线:多源采集 → LLM 清洗增强 → 去重 → 按 id 合并 → 写回
`apps/ios/FreshPantry/Resources/howtocook.json`。

## 用法
1. `cp .env.example .env` 填 `ANTHROPIC_API_KEY`
2. 预览(限量、不写盘):`npm run build:recipes:dry`
3. 全量:`npm run build:recipes`
4. 测试:`npm test`

CLI 直接调用:`flue run build-recipes --target node --payload '{"limit":3,"dryRun":true}'`
(payload 支持 `limit` / `dryRun` / `refreshDescriptions`)

## 扩充来源
编辑 `data/sources.json`,加 `markdown-repo`(通用中文菜谱 git 仓库)或 `url-batch`
(任意菜谱网页)条目,字段见 `src/sources/registry.ts` 的 `SourceConfig`。首期默认只启用 `howtocook`。

## 架构
- 采集层(`src/sources/`,可插拔 `RecipeSource`)只产出统一 `RawRecipe`。
- 纯 TS 核心(`src/parse` `src/clean` `src/pipeline.ts`)不依赖 flue,可全单测。
- LLM 调用藏在 `RecipeEnricher` 接口后;flue 仅出现在 `src/agents/` `src/clean/flue-enricher.ts` `src/workflows/`。

## 合并保护(对已上线数据)
按 id 合并:既有 `imageUrl`/`remoteVersion`/软删保留,`description` 黏住(除非 `--refreshDescriptions`),
食材用量「只抽不猜」回填。既有 json 损坏时拒绝覆盖。详见
`docs/superpowers/specs/2026-06-12-recipe-collection-cleaning-pipeline-design.md`。
