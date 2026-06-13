# 本地 Feature Flag 机制 — 设计文档

- 日期:2026-06-13
- 范围:`apps/ios/FreshPantry`(SwiftUI)
- 状态:已通过 brainstorming 确认,待写实现计划

## 目标

为 iOS app 建一套**通用、纯本地、零 schema 改动**的 feature flag 机制:

- 把未完成 / 实验性功能先合进 `main`、生产环境隐藏,需要时随时开启测试。
- 通过**隐藏调试菜单**切换,普通用户不会误触。
- 适配 **TestFlight 真机测试**(release 构建):解锁靠运行期手势,不靠 `#if DEBUG`,所以 DEBUG / TestFlight / 生产都能进。
- 附带一个**示例 flag** 跑通端到端,证明「解锁调试菜单 → 切换 flag → 别处即时生效」。

## 已确认决策

| 维度 | 决策 |
| --- | --- |
| 真相来源 | 纯本地:编译期默认值 + UserDefaults 覆盖。无后端、无表、无同步。 |
| 切换入口 | 隐藏调试菜单(开发 / QA 用)。 |
| 可见性门禁 | 隐藏手势解锁:Settings 连点「版本」行 **7 次** → 解锁。运行期判断,生产也能进。 |
| 首个 flag | 只建机制 + 一个无害示例 flag(`demoFeature`)。 |
| flag 值类型 | 仅布尔(YAGNI;多变体 / 字符串后置)。 |
| 解锁状态 | 持久化(测试者点一次即可,不必每次启动重点)。 |
| 备份 / 同步 | flag 覆盖值与解锁状态均**设备本地**,排除备份与家庭同步(同 `AppearanceStore`)。 |

## 架构

沿用现有约定:KV-settings-store 模板(`AppearanceStore` / `FavoritesStore`)+ `AppDependencies` 集中注入 + `SettingsView` section 结构。新文件归入新建的 `Features/Debug/` 模块(按来源功能内聚,同 `FavoritesStore` 虽全局消费但归 `Features/Recipes`)。

### 组件

**1. `FeatureFlag.swift`(`Features/Debug/`)— flag 注册表(唯一真相)**

```swift
enum FeatureFlag: String, CaseIterable, Sendable {
    case demoFeature   // 示例 flag

    var title: String { ... }        // 调试菜单显示名
    var summary: String { ... }      // 一句话说明
    var defaultValue: Bool { ... }   // 编译期默认值(WIP 一般 false)
}
```

- `rawValue` 即 UserDefaults 覆盖存储的 key。
- 新增 flag = 加一个 case + 三个属性。这是「存在哪些 flag」的单一真相。

**2. `FeatureFlagStore.swift`(`Features/Debug/`)— 仿 `AppearanceStore` 模板**

- `@Observable @MainActor`,UserDefaults backing,**可注入 suite**(测试隔离)。
- 只存**覆盖值**:`[String: Bool]` 编码为 JSON,存于 key `feature_flag_overrides_v1`。
- 无覆盖 → 回落到 `flag.defaultValue`。存覆盖而非全量值,保证「改默认值」对未显式覆盖的 flag 立即生效。
- API:
  - `isEnabled(_ flag: FeatureFlag) -> Bool` — 有覆盖取覆盖,否则取 `defaultValue`。
  - `set(_ flag: FeatureFlag, _ on: Bool)` — 写覆盖并持久化。
  - `reset(_ flag: FeatureFlag)` — 清单个覆盖,回落默认。
  - `resetAll()` — 清空所有覆盖。
  - `isOverridden(_ flag: FeatureFlag) -> Bool` — 供调试菜单显示「已覆盖 / 默认」。
- 防御式 decode:nil / 空 / 非 dict / 恶意 JSON → 空覆盖表(同 `FavoritesStore` 的 lenient load)。

**3. `DebugMenuGate.swift`(`Features/Debug/`)— 解锁状态(独立小职责)**

- `@Observable @MainActor`,UserDefaults backing,可注入 suite。
- 持久化布尔,key `debug_menu_unlocked_v1`。
- API:`isUnlocked` / `unlock()` / `lock()`。
- 与 flag 值解耦:门控「调试菜单是否可见」,不掺 flag 逻辑。

**4. `DebugMenuView.swift`(`Features/Debug/`)**

- 从 `@Environment(AppDependencies.self)` 取 store。
- 遍历 `FeatureFlag.allCases`,每个一行 `Toggle`(绑定 `store.isEnabled` ↔ `store.set`),副标题显示 `summary` + 「已覆盖 / 默认」状态。
- 底部:「重置全部」(`resetAll()`)+「锁定调试菜单」(`gate.lock()`,退出后入口消失)。

### 接线(2 处改动)

**`AppDependencies.swift`**

- 新增 `let featureFlagStore: FeatureFlagStore` 与 `let debugMenuGate: DebugMenuGate`。
- init 里无参构建(同 `self.appearanceStore = AppearanceStore()`)。

**`SettingsView.swift`**

- `aboutSection` 的「版本」行加连点手势:`@State private var versionTapCount`,累计达 **7** 调 `debugMenuGate.unlock()` 并触发触感反馈、清零计数。
- 新增 `debugSection`:仅当 `debugMenuGate.isUnlocked` 时渲染,内含 NavigationLink → `DebugMenuView`(标题「调试菜单」)。插入 section 列表(置于 `aboutSection` 前或后,实现时定)。

### 示例 flag 端到端验证

`demoFeature` 默认 `false`。开启时,在 Settings 显示一条「🎉 示例功能已开启」演示行(仅当 `featureFlagStore.isEnabled(.demoFeature)`)。

验证链路:解锁调试菜单 → 切换 `demoFeature` 为 on → 返回 Settings,演示行**即时出现**(靠 `@Observable` 观测,无需重启)。这证明跨屏消费路径成立。

## 数据流

```
SettingsView「版本」行 ──连点7次──▶ DebugMenuGate.unlock() ──持久化──▶ UserDefaults
                                              │
                                  isUnlocked=true 触发 @Observable
                                              ▼
SettingsView debugSection 显示 ──NavigationLink──▶ DebugMenuView
                                                        │
                                            Toggle ↔ FeatureFlagStore.set/isEnabled
                                                        │ 持久化覆盖
                                                        ▼
                                                  UserDefaults (feature_flag_overrides_v1)
                                                        │
                                       任意视图 featureFlagStore.isEnabled(.x) 即时读
```

## 错误处理与边界

- **持久化失败**:JSON 编码失败时静默不写(同 `FavoritesStore.persist` 的 `guard ... else { return }`),内存值仍生效本次会话。
- **恶意 / 损坏的 UserDefaults**:decode 一律回落空覆盖表 / 锁定态,不崩溃。
- **未知 key**:覆盖表里出现已删除 flag 的 key 时,`isEnabled` 只查 `allCases`,陈旧 key 被忽略(不报错,下次 `resetAll` 自然清掉)。
- **启动期读取的 flag**:本机制不解决「改 flag 需重启」——门控启动期一次性读取的功能时,可能需重启 app。示例 flag 走实时读取路径,不受此限。超出本次范围。

## 测试(`FreshPantryTests/`)

沿用 store 测试惯例(注入隔离的 `UserDefaults(suiteName:)`)。

**`FeatureFlagStoreTests`**
- 无覆盖 → `isEnabled` 返回 `defaultValue`。
- `set(true/false)` 后 `isEnabled` 读回正确值,`isOverridden` 为 true。
- `reset` 单个 → 回落 `defaultValue`,`isOverridden` 为 false。
- `resetAll` → 全部回落默认。
- 跨实例持久化:同 suite 新建 store 能读到上个实例写的覆盖。
- 恶意 JSON / 非 dict / 空串 → 防御 decode 为空覆盖表。
- suite 隔离:不同 suite 互不串值。

**`DebugMenuGateTests`**
- 默认锁定(`isUnlocked == false`)。
- `unlock()` 持久化:同 suite 新实例读到 unlocked。
- `lock()` 复位并持久化。

**`FeatureFlagRegistryTests`**
- 每个 `FeatureFlag.allCases` 的 `title` / `summary` 非空(注册表 sanity)。

## XcodeGen

`apps/ios/project.yml` 的 `FreshPantry` target 用目录 glob(`path: FreshPantry` + excludes),`FreshPantryTests` 同理。`Features/Debug/` 下的新文件与新测试在 `xcodegen generate` 后自动纳入,**无需改 `project.yml`**。

## 不做(YAGNI / 超出范围)

- 远程拉取 / 灰度 / kill switch(已选纯本地;接口也不预留 remote provider)。
- 多变体 / 字符串 / 数值 flag(仅布尔)。
- flag 分组、依赖、过期清理自动化。
- 用户可见的「实验室」设置区(已选仅隐藏调试菜单)。
- 解决「改 flag 需重启」的通用响应式刷新。
