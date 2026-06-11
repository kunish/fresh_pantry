# 设置页「我」卡片（个人资料入口可发现性）设计稿

- 日期：2026-06-11
- 状态：已评审，待实现计划
- 范围：iOS 端单文件 `SettingsView.swift`（复用现有组件，无 schema / 数据层改动）
- 关联：[2026-06-11-personal-profile-design.md](./2026-06-11-personal-profile-design.md)

## 1. 背景

个人资料功能（头像 / 名称 / 昵称的 onboarding、显示、编辑）已落地，编辑功能本身**完整可用**：
`ProfileEditView`（`mode: .settings`）能加载现有头像/名称/昵称并保存。

问题出在**入口可发现性**。原个人资料 spec §5.2 明确要求：

> `Features/Settings/SettingsView.swift` | **顶部**「个人资料」入口行（**头像 + 名称**），进入 `ProfileEditView`

但实际实现（commit `7afd48e`）偏离了该意图——入口落在了**「账号·家庭」分组的第二层**，是一行**纯文字 + 图标**（`person.text.rectangle`），既不在顶部、也没有头像。结果是连维护者本人都没在设置里找到它。

按本项目 self-use / A-mode 定位（优化维护者摩擦），可发现性弱是个值得修正的真实问题。

## 2. 目标

把个人资料编辑入口从「藏在账号分组里的一行文字」**拉回原设计意图**：设置页**第一眼可见**、**带头像**、**整卡可点**进入编辑。

非目标（YAGNI）：
- 不扩展可编辑字段（头像/名称/昵称三项不变）。
- 不动 Flutter 端（仍留作后续 parity）。
- 不碰家庭成员列表的「我」行（方案 C，未采纳）。
- 不重写编辑/保存逻辑（`ProfileEditView` / `ProfileStore` 不变）。

## 3. 方案（顶部「我」卡片）

设置页 `Form` 最顶新增一个 `profileCardSection`，置于 `statsSection` 之前；从 `accountSection` 移除原「个人资料」行，避免双入口。

```
设置
┌─────────────────────────┐
│ ╭──────────────────────╮ │
│ │ ●  小白               │ │  ← 整卡 Button，点击
│ │头像 昵称/邮箱       › │ │  → showProfileEditor = true
│ ╰──────────────────────╯ │
├─────────────────────────┤
│ [12 食材][3 采购][5 收藏] │   ← 原 statsSection
├─────────────────────────┤
│ 账号 · 家庭                │
│  账号                     │   ← 原「个人资料」行已移除
│  家庭共享                  │
└─────────────────────────┘
```

### 3.1 卡片内容

整行是 `Button { showProfileEditor = true }`，复用现有的 `$showProfileEditor` 状态与 `.sheet`（零新增状态）。布局：

| 元素 | 来源 | 回退 |
|---|---|---|
| 头像 | `MemberAvatar(displayName:avatarURL:size: 52)`（复用 `MemberRow.swift` 既有共享组件） | 无头像时显示名称首字母色块（组件已内置） |
| 主标题（名称） | `profileStore.displayName` | 为空时显示「设置头像与名称」（沿用现有 `profileSubtitle` 文案） |
| 副标题 | `profileStore.nickname`（trimmed 非空时） | 否则 `accountSubtitle`（签到态邮箱 / 「未配置后端·本地模式」/「登录以同步家庭数据」） |
| 尾部 | `chevron.right`（次要色） | — |

副标题优先级即 **昵称 → 邮箱/账号状态**（已确认）。

### 3.2 视觉与一致性

- `listRowBackground(Color.fkSurfaceContainerLowest)`，与现有各 section 一致。
- 头像 52pt（比成员行 40pt 略大以承担顶部主卡片的视觉权重）。
- 卡片行用 `Button` + `.buttonStyle(.plain)`，沿用 `accountSection` 现有「个人资料」按钮的交互写法。

## 4. 改动清单

**修改（1 文件）**
- `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`
  - 新增 `private var profileCardSection`（含一个本地 `ProfileCardRow` 私有视图或内联布局）。
  - `body` 的 `Form` 中把 `profileCardSection` 置于 `statsSection` 之前。
  - 从 `accountSection` 删除「个人资料」`Button`（约 `:124-134`）；`.sheet(isPresented: $showProfileEditor)` 移到 `profileCardSection`（或保持 body 层级可见）。
  - `profileSubtitle` 若不再被 account 行引用，并入卡片逻辑（避免悬挂）。

**复用（不改）**
- `MemberAvatar`（`Features/Household/MemberRow.swift`）— 圆形头像 + 首字母回退。
- `ProfileStore` / `ProfileEditView` — 数据与编辑表单。

## 5. 测试与验证

- 本改动为纯 UI 重排，无逻辑分支新增，依赖现有 `ProfileStoreTests` 覆盖名称回退优先级。
- 手测项：
  1. 有头像/名称/昵称 → 卡片显示头像 + 名称 + 昵称，点击进编辑，保存后卡片实时刷新。
  2. 仅名称无昵称 → 副标题回退为邮箱。
  3. 名称为空（理论上 onboarding 后不会出现）→ 主标题显示「设置头像与名称」，头像回退首字母。
  4. 本地模式（未配后端）→ 副标题「未配置后端·本地模式」，头像为首字母。
- 确认 `accountSection` 不再出现重复的「个人资料」行。

## 6. 风险

- 低。单文件 UI 重排，复用既有组件，不触碰数据/同步/schema。
- 唯一需注意：删除 account 行后，`profileSubtitle` 等辅助计算属性的引用要清理干净，避免编译告警/死代码。
