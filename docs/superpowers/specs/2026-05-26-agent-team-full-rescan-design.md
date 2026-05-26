# Agent Team 全量重扫 — 设计 Spec

**日期:** 2026-05-26
**目标项目:** fresh_pantry（Flutter + Riverpod，~13k LOC）
**前序报告:** `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`
**状态:** 已通过用户批准，等待实施计划

---

## 1. 目标

派遣 4 个 Explore subagent（Quality / Perf / Test / UX）并行全量扫描当前 `lib/` + `test/`，合并报告后由 Lead 串行实施低风险改动并就高风险项与用户决策。

本次是 2026-05-07 运行的**延续**：旧报告的 `pending` 条目按文件合并到新报告（携带 `carried-from-2026-05-07` 标记），不单独维护旧报告。

## 2. 非目标

- 不重新设计整体架构（分层、状态管理选型保持不变）
- 不引入新 pub 依赖（除非 HIGH 项被批准）
- 不修改 `build/`、`.dart_tool/`、平台目录、配置文件
- 不建立长期 agent team 配置文件

## 3. 扫描范围

**包含**
- `lib/**/*.dart`
- `test/**/*.dart`

**排除**
- `build/`、`.dart_tool/`
- `*.g.dart`、`*.freezed.dart`（生成代码）
- 平台目录：`android/`、`ios/`、`macos/`、`linux/`、`windows/`、`web/`
- `docs/`
- 配置文件：`pubspec.yaml`、`analysis_options.yaml`、`.metadata`

## 4. 执行模式

**实施优先**：发现低风险问题直接改，高风险才请用户拍板。

### 4.1 风险边界（LOW = 直改，HIGH = 待批准）

**LOW（直改）**
- 重命名局部变量、私有方法、单文件内符号
- 删除 dead code（grep 确认 0 引用）
- 提取局部常量（scope 在单文件内）
- 补单元测试（纯新增，不动现有测试）
- 修 lint 与 dart format 问题
- 一致化 import 顺序

**HIGH（待批准）**
- Provider 拆分/合并
- Storage / Service 接口签名变更
- Widget public API（props、callback 签名）变更
- 跨屏数据流重组
- 添加或删除 pub 依赖
- 提取全局常量
- 跨文件合并/拆分 widget
- 修改依赖注入结构

## 5. Team 组成

| Agent | subagent_type | 关注范围 | 职责 |
|-------|--------------|---------|------|
| Quality Explorer | `Explore` | `lib/**/*.dart`（排除 `lib/data/` 纯数据常量） | 重复代码、过长函数（>60 行）、命名不一致、过度抽象、dead code |
| Perf Explorer | `Explore` | `lib/screens/`、`lib/widgets/`、`lib/providers/` | 不必要 rebuild、selector 缺失、ListView 未用 builder、autoDispose 缺失、build 内 allocation |
| Test Explorer | `Explore` | `test/`、`lib/providers/`、`lib/utils/` | 测试盲点（provider 行为/边界值/错误路径）、关键屏幕无 widget 测试、弱断言 |
| UX Explorer | `Explore` | `lib/screens/`、`lib/widgets/`、`lib/theme/` | theme token 不一致、空态/加载态/错误态缺失、a11y 问题、响应式溢出、UI 重复 |
| Lead（主对话） | — | 协调全局 | 合并报告、风险分类、旧 pending 合并、串行实施、commit、与用户交互 |

**执行权限**：Explorer 全部只读（`Explore` subagent_type 无 Edit/Write）；实施阶段 Lead 自己改代码。

## 6. 工作流（三阶段）

### 阶段 1：并行研究

Lead 在**单条消息内**并行派发 4 个 Explorer agent。每个 agent 收到的 prompt 包含：
- 关注范围（table 中列出的目录/文件 glob）
- 报告格式契约（见 §7）
- 严格要求「只读分析，不要修改任何文件」
- 输出上限：每个 agent ≤ 50 个 issue（超出时按 severity 降序、同 severity 按 risk(HIGH 优先)、再按 file 字典序取前 50）

### 阶段 2：Lead 合并 + 风险打标

1. **解析**：把 4 份 markdown 表格每行转为内部数据（file_line, severity, category, issue, proposal, risk, source）
2. **合并旧 pending**：从 `2026-05-07-agent-team-optimization-report.md` 提取 Status = `pending` 的行，加入合并集，Source 字段标 `carried-from-2026-05-07`
3. **去重**：同一 (file, line) 多 agent 命中 → 合并一行，Source 累加，severity/risk 取最高
4. **风险复核**：按 §4.1 规则复核每行的 Risk
5. **冲突检测**：同文件同时有 HIGH 与 LOW 项，给 LOW 项标 `blocked-by-high`
6. **写入报告**：统一报告写入 `docs/superpowers/specs/2026-05-26-agent-team-full-rescan-report.md`
7. **向用户呈现**：LOW 总览（数量/影响文件/类别分布）一次性批准；HIGH 一项一项过

### 阶段 3：串行实施

按文件分组实施（同文件所有 LOW 改动合到一个 commit batch）：

1. 每个 commit 前：`flutter analyze`（基线）
2. 实施改动
3. 每个 commit 后：`flutter analyze` + `flutter test`（全量）
4. 失败立即 `git revert`，问题记入 "Failed Items" 段
5. Commit 格式：`opt(<agent>): <一句话总结>`

## 7. 报告格式契约

每个 Explorer agent 必须返回（无变体）：

````markdown
## <Agent Name> Findings

Summary: <一句话总结发现的主要问题类型>

| File:Line | Severity | Category | Issue | Proposal | Risk |
|-----------|----------|----------|-------|----------|------|
| lib/foo/bar.dart:42 | medium | duplication | 描述 | 具体动作 | LOW |

Notes (optional): <全局观察，可省略>
````

**字段定义**
- **File:Line** — 项目内相对路径，行号指向问题起始行
- **Severity** — `low` / `medium` / `high`
- **Category** — 短词（`duplication`、`rebuild`、`missing-test`、`a11y` 等）
- **Issue** — 1-2 句客观描述
- **Proposal** — 具体修复动作（不是模糊描述）
- **Risk** — `LOW` / `HIGH`，Explorer 初判，Lead 复核

**新报告合并表额外列**
- **Source** — agent 名（逗号分隔多命中），旧条目加 `carried-from-2026-05-07`
- **Decision** — `auto-approved` / `pending` / `blocked-by-high` / `approved` / `deferred` / `rejected`
- **Status** — `pending` / `done` / `failed` / `reverted` / `skipped`

## 8. 错误与冲突处理

- **Agent 失败/超时**：不阻塞其他 3 个，记录到 "Failed Agents" 段
- **格式不合规**：允许 1 次重发；仍失败则手工解析，记录"格式不合规已手工解析"
- **commit 后测试失败**：立即 `git revert`，记入 "Failed Items"
- **flutter analyze 引入新 warning**：与失败同等处理（revert）

## 9. 成功标准

- [ ] 4 份 Explorer 报告全部产出（或失败有记录）并合并到报告
- [ ] 旧 pending 条目全部携带 `carried-from-2026-05-07` 标记并入新报告
- [ ] 所有 Decision = approved/auto-approved 的项 Status = done（或 failed/reverted 已记录）
- [ ] `flutter analyze` 0 error / 0 warning 新增
- [ ] `flutter test` all pass
- [ ] 至少 1 个新增测试覆盖 Test Explorer 盲点
- [ ] 所有 HIGH 项 Decision 不为 pending
- [ ] 总 commit 数 < 受影响文件数
- [ ] 报告中 "Failed Agents"、"Failed Items" 段存在（可为空）

## 10. 产出物清单

执行完毕后，以下文件存在并已 commit：

1. `docs/superpowers/specs/2026-05-26-agent-team-full-rescan-design.md` — 本文件
2. `docs/superpowers/specs/2026-05-26-agent-team-full-rescan-report.md` — 合并报告与决策记录
3. `docs/superpowers/plans/2026-05-26-agent-team-full-rescan.md` — 实施计划（由 writing-plans skill 产出）
4. 一系列 `opt(<agent>): ...` commit，实现 LOW 与已批准的 HIGH 项

## 11. 与 2026-05-07 报告的关系

- 旧报告保留不删除，作为历史参考
- 旧报告中 Status = `done`/`failed`/`reverted`/`skipped` 的条目不迁移（已处理）
- 旧报告中 Status = `pending` 的条目全部迁移到新报告，加 `carried-from-2026-05-07` 标记
- 新报告是后续实施的唯一工作文档

## 12. 已知限制

- Explorer ≤ 50 issue 上限可能漏掉次要问题（可接受，聚焦高价值）
- 跨 agent 语义重叠靠 Lead 在合并阶段识别，可能有少量重复条目
- 旧 pending 条目的 file:line 在三周后可能已行号漂移，合并时按文件+描述模糊匹配
