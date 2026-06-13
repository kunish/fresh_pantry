# 本地 Feature Flag 机制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 iOS app 建一套纯本地、零 schema 改动的 feature flag 机制,通过隐藏调试菜单(连点版本号 7 次解锁)切换,附一个示例 flag 跑通端到端。

**Architecture:** 沿用现有 KV-settings-store 模板(`AppearanceStore`/`FavoritesStore`):`@Observable @MainActor` + UserDefaults backing + 可注入 suite + 防御式 decode。新增 4 个文件归入新建的 `Features/Debug/` 模块,经 `AppDependencies` 集中注入;`SettingsView` 加连点解锁手势与 `debugSection`。flag 值仅布尔,只存覆盖值(无覆盖回落编译期默认)。

**Tech Stack:** SwiftUI、SwiftData(仅作为 DI 容器载体)、swift-testing(`import Testing` / `@Test` / `#expect`)、XcodeGen(目录 glob,新文件需 `xcodegen generate` 后纳入)。

---

## 设计来源

依据 `docs/superpowers/specs/2026-06-13-feature-flags-design.md`(commit `95b9c65`)。

## 文件结构

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `apps/ios/FreshPantry/Features/Debug/FeatureFlag.swift` | flag 注册表:枚举 + title/summary/defaultValue | 新建 |
| `apps/ios/FreshPantry/Features/Debug/FeatureFlagStore.swift` | UserDefaults 覆盖值 store(isEnabled/set/reset/resetAll/isOverridden) | 新建 |
| `apps/ios/FreshPantry/Features/Debug/DebugMenuGate.swift` | 调试菜单解锁状态(isUnlocked/unlock/lock) | 新建 |
| `apps/ios/FreshPantry/Features/Debug/DebugMenuView.swift` | 调试菜单 UI:flag toggles + 重置/锁定 | 新建 |
| `apps/ios/FreshPantry/App/AppDependencies.swift` | 注入两个新 store | 改 |
| `apps/ios/FreshPantry/Features/Settings/SettingsView.swift` | 连点解锁手势 + debugSection + demo 行 | 改 |
| `apps/ios/FreshPantryTests/FeatureFlagRegistryTests.swift` | 注册表 sanity | 新建 |
| `apps/ios/FreshPantryTests/FeatureFlagStoreTests.swift` | store 单测 | 新建 |
| `apps/ios/FreshPantryTests/DebugMenuGateTests.swift` | gate 单测 | 新建 |

## 可复用命令(REGEN + TEST)

> 所有 `cd` 基于仓库根 `apps/ios`。新建 `.swift` 文件后**必须先 regen**(XcodeGen 才会把文件纳入 target),否则编译时报「cannot find ... in scope」。本机已存在 `FreshPantry/Support/Secrets.plist`(gitignored),无需重新生成。

**REGEN:**
```bash
cd apps/ios && xcodegen generate
```

**TEST(可加 `-only-testing:FreshPantryTests/<套件名>` 缩范围):**
```bash
cd apps/ios
UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; c=[v for rt in d for v in d[rt] if v.get('isAvailable') and v['name'].startswith('iPhone')]; print(c[0]['udid'] if c else '')")
[ -z "$UDID" ] && { echo 'no available iPhone simulator'; exit 1; }
xcodebuild test -project FreshPantry.xcodeproj -scheme FreshPantry -destination "platform=iOS Simulator,id=$UDID"
```

**BUILD ONLY(仅编译,验证接线/视图):** 把上面的 `test` 换成 `build-for-testing`。

> 注:swift-testing 下,测试文件引用尚不存在的类型会让整个测试 target **编译失败**——这就是 TDD 的「红」。实现后转「绿」。

---

### Task 1: FeatureFlag 注册表

**Files:**
- Create: `apps/ios/FreshPantry/Features/Debug/FeatureFlag.swift`
- Test: `apps/ios/FreshPantryTests/FeatureFlagRegistryTests.swift`

- [ ] **Step 1: 写失败测试**

Create `apps/ios/FreshPantryTests/FeatureFlagRegistryTests.swift`:

```swift
import Testing
@testable import FreshPantry

/// 注册表 sanity:每个 flag 的展示元数据非空,且至少存在示例 flag。
struct FeatureFlagRegistryTests {
    @Test func everyFlagHasNonEmptyMetadata() {
        for flag in FeatureFlag.allCases {
            #expect(!flag.title.isEmpty)
            #expect(!flag.summary.isEmpty)
        }
    }

    @Test func demoFeatureExistsAndDefaultsOff() {
        #expect(FeatureFlag.allCases.contains(.demoFeature))
        #expect(FeatureFlag.demoFeature.defaultValue == false)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败(红)**

Run REGEN, then TEST with `-only-testing:FreshPantryTests/FeatureFlagRegistryTests`.
Expected: 编译失败,`cannot find 'FeatureFlag' in scope`。

- [ ] **Step 3: 实现 FeatureFlag**

Create `apps/ios/FreshPantry/Features/Debug/FeatureFlag.swift`:

```swift
import Foundation

/// 所有 feature flag 的注册表 —— 「存在哪些 flag」的单一真相。每个 case 携带
/// 调试菜单展示元数据与编译期默认值。新增 flag = 加一个 case + 三个属性分支。
/// `rawValue` 同时用作 UserDefaults 覆盖键,故重命名 case 会丢弃已存覆盖(可接受:
/// 覆盖是设备本地调试状态,非用户数据)。
///
/// 纯本地:取值 = 编译期 `defaultValue` + `FeatureFlagStore` 的可选设备覆盖,
/// 无后端/无 schema/无同步(见 `2026-06-13-feature-flags-design.md`)。
enum FeatureFlag: String, CaseIterable, Sendable {
    /// 无害示例 flag,证明端到端链路(调试切换 → Settings 行即时出现)。
    /// 默认关闭,可安全随包发布。
    case demoFeature

    /// 调试菜单行标题。
    var title: String {
        switch self {
        case .demoFeature: "示例功能"
        }
    }

    /// 调试菜单一句话说明。
    var summary: String {
        switch self {
        case .demoFeature: "演示用开关:开启后设置页出现一条演示行"
        }
    }

    /// 无设备覆盖时的编译期默认值。WIP flag 一律发 `false`。
    var defaultValue: Bool {
        switch self {
        case .demoFeature: false
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过(绿)**

Run REGEN, then TEST with `-only-testing:FreshPantryTests/FeatureFlagRegistryTests`.
Expected: PASS(2 tests)。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/FreshPantry/Features/Debug/FeatureFlag.swift apps/ios/FreshPantryTests/FeatureFlagRegistryTests.swift
git commit -m "feat(ios): add FeatureFlag registry"
```

---

### Task 2: FeatureFlagStore

**Files:**
- Create: `apps/ios/FreshPantry/Features/Debug/FeatureFlagStore.swift`
- Test: `apps/ios/FreshPantryTests/FeatureFlagStoreTests.swift`

- [ ] **Step 1: 写失败测试**

Create `apps/ios/FreshPantryTests/FeatureFlagStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

/// UserDefaults 覆盖值 store:默认回落、覆盖读回、reset/resetAll、跨实例持久化、
/// 防御式 decode、suite 隔离。
@MainActor
struct FeatureFlagStoreTests {
    /// 每个测试一个隔离 suite,持久值不串。
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.featureflag.\(UUID().uuidString)")!
    }

    // MARK: 默认回落

    @Test func freshStoreReturnsCompiledDefault() {
        let store = FeatureFlagStore(defaults: suite())
        #expect(store.isEnabled(.demoFeature) == FeatureFlag.demoFeature.defaultValue)
        #expect(store.isOverridden(.demoFeature) == false)
    }

    // MARK: 覆盖 + 持久化

    @Test func setOverridesAndPersists() {
        let defaults = suite()
        let store = FeatureFlagStore(defaults: defaults)

        store.set(.demoFeature, true)
        #expect(store.isEnabled(.demoFeature) == true)
        #expect(store.isOverridden(.demoFeature) == true)

        // 同 suite 新实例读到持久覆盖。
        let reloaded = FeatureFlagStore(defaults: defaults)
        #expect(reloaded.isEnabled(.demoFeature) == true)
        #expect(reloaded.isOverridden(.demoFeature) == true)
    }

    // MARK: reset / resetAll

    @Test func resetClearsSingleOverride() {
        let store = FeatureFlagStore(defaults: suite())
        store.set(.demoFeature, true)
        store.reset(.demoFeature)
        #expect(store.isOverridden(.demoFeature) == false)
        #expect(store.isEnabled(.demoFeature) == FeatureFlag.demoFeature.defaultValue)
    }

    @Test func resetAllClearsEverything() {
        let defaults = suite()
        let store = FeatureFlagStore(defaults: defaults)
        store.set(.demoFeature, true)
        store.resetAll()
        #expect(store.isOverridden(.demoFeature) == false)
        // 持久化:同 suite 新实例也看不到覆盖。
        #expect(FeatureFlagStore(defaults: defaults).isOverridden(.demoFeature) == false)
    }

    // MARK: 防御式 decode

    @Test func decodeHandlesNilEmptyAndMalformed() {
        #expect(FeatureFlagStore.decode(nil).isEmpty)
        #expect(FeatureFlagStore.decode("").isEmpty)
        #expect(FeatureFlagStore.decode("not json").isEmpty)
        // 顶层数组而非对象 → 空。
        #expect(FeatureFlagStore.decode("[1,2,3]").isEmpty)
        // 合法对象:bool 值保留,非 bool 字符串值丢弃。
        let decoded = FeatureFlagStore.decode("{\"demoFeature\":true,\"x\":\"nope\"}")
        #expect(decoded["demoFeature"] == true)
        #expect(decoded["x"] == nil)
    }

    // MARK: suite 隔离

    @Test func suitesAreIsolated() {
        let a = FeatureFlagStore(defaults: suite())
        let b = FeatureFlagStore(defaults: suite())
        a.set(.demoFeature, true)
        #expect(b.isOverridden(.demoFeature) == false)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败(红)**

Run REGEN, then TEST with `-only-testing:FreshPantryTests/FeatureFlagStoreTests`.
Expected: 编译失败,`cannot find 'FeatureFlagStore' in scope`。

- [ ] **Step 3: 实现 FeatureFlagStore**

Create `apps/ios/FreshPantry/Features/Debug/FeatureFlagStore.swift`:

```swift
import Foundation

/// UserDefaults backing 的 feature-flag 覆盖值 —— 沿用 `AppearanceStore` /
/// `FavoritesStore` 的 KV 模板:`@Observable @MainActor`、可注入 suite、防御式
/// decode。只存**每-flag 覆盖**(`[String: Bool]` JSON 对象,key
/// `feature_flag_overrides_v1`,键为 `FeatureFlag.rawValue`)。无覆盖回落到
/// `FeatureFlag.defaultValue`,所以改某 flag 的编译期默认值会立刻影响所有未显式
/// 覆盖该 flag 的设备。设备本地:排除备份 / 家庭同步。
@Observable
@MainActor
final class FeatureFlagStore {
    static let storageKey = "feature_flag_overrides_v1"

    private let defaults: UserDefaults

    /// 按 `FeatureFlag.rawValue` 键存的实时覆盖表;缺键 → 回落编译期默认。
    /// 改动同步持久化。
    private(set) var overrides: [String: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: 查询

    /// 有效值:有设备覆盖取覆盖,否则取编译期默认。
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        overrides[flag.rawValue] ?? flag.defaultValue
    }

    /// 是否存在设备覆盖(驱动「已覆盖 / 默认」标签)。
    func isOverridden(_ flag: FeatureFlag) -> Bool {
        overrides[flag.rawValue] != nil
    }

    // MARK: 变更

    /// 设置(覆盖)某 flag 并持久化。
    func set(_ flag: FeatureFlag, _ on: Bool) {
        overrides[flag.rawValue] = on
        persist()
    }

    /// 清单个 flag 的覆盖 → 回落编译期默认。
    func reset(_ flag: FeatureFlag) {
        overrides[flag.rawValue] = nil
        persist()
    }

    /// 清空所有覆盖 → 全部回落编译期默认。
    func resetAll() {
        overrides = [:]
        persist()
    }

    // MARK: 持久化(JSON 对象 KV 编解码,镜像 FavoritesStore)

    /// 把覆盖表编码为 JSON 对象写入。编码失败静默不写(本会话内存值仍生效)。
    private func persist() {
        guard
            let data = try? JSONSerialization.data(withJSONObject: overrides),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// 防御式 decode:nil/空/非对象/损坏 → 空覆盖表;否则取 `String: Bool` 条目
    /// (非 bool 值丢弃)。
    static func decode(_ raw: String?) -> [String: Bool] {
        guard
            let raw, !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object.compactMapValues { $0 as? Bool }
    }
}
```

- [ ] **Step 4: 跑测试确认通过(绿)**

Run REGEN, then TEST with `-only-testing:FreshPantryTests/FeatureFlagStoreTests`.
Expected: PASS(6 tests)。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/FreshPantry/Features/Debug/FeatureFlagStore.swift apps/ios/FreshPantryTests/FeatureFlagStoreTests.swift
git commit -m "feat(ios): add FeatureFlagStore (UserDefaults override store)"
```

---

### Task 3: DebugMenuGate

**Files:**
- Create: `apps/ios/FreshPantry/Features/Debug/DebugMenuGate.swift`
- Test: `apps/ios/FreshPantryTests/DebugMenuGateTests.swift`

- [ ] **Step 1: 写失败测试**

Create `apps/ios/FreshPantryTests/DebugMenuGateTests.swift`:

```swift
import Foundation
import Testing
@testable import FreshPantry

/// 调试菜单解锁状态:默认锁定、unlock 持久化、lock 复位。
@MainActor
struct DebugMenuGateTests {
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.debugmenugate.\(UUID().uuidString)")!
    }

    @Test func freshGateIsLocked() {
        #expect(DebugMenuGate(defaults: suite()).isUnlocked == false)
    }

    @Test func unlockPersists() {
        let defaults = suite()
        let gate = DebugMenuGate(defaults: defaults)
        gate.unlock()
        #expect(gate.isUnlocked == true)
        // 同 suite 新实例读到 unlocked。
        #expect(DebugMenuGate(defaults: defaults).isUnlocked == true)
    }

    @Test func lockResetsAndPersists() {
        let defaults = suite()
        let gate = DebugMenuGate(defaults: defaults)
        gate.unlock()
        gate.lock()
        #expect(gate.isUnlocked == false)
        #expect(DebugMenuGate(defaults: defaults).isUnlocked == false)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败(红)**

Run REGEN, then TEST with `-only-testing:FreshPantryTests/DebugMenuGateTests`.
Expected: 编译失败,`cannot find 'DebugMenuGate' in scope`。

- [ ] **Step 3: 实现 DebugMenuGate**

Create `apps/ios/FreshPantry/Features/Debug/DebugMenuGate.swift`:

```swift
import Foundation

/// UserDefaults backing 的隐藏调试菜单解锁状态。沿用 `AppearanceStore` KV 模板:
/// `@Observable @MainActor`、可注入 suite。持久化(key `debug_menu_unlocked_v1`)
/// 使测试者解锁一次后,调试菜单入口跨启动保留 —— 包括 TestFlight / 生产构建,
/// 因为这是运行期开关而非 `#if DEBUG` 守卫。设备本地:排除备份 / 家庭同步。
@Observable
@MainActor
final class DebugMenuGate {
    static let storageKey = "debug_menu_unlocked_v1"

    private let defaults: UserDefaults

    /// Settings 里是否显示隐藏的「调试菜单」入口。
    private(set) var isUnlocked: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isUnlocked = defaults.bool(forKey: Self.storageKey)
    }

    /// 显示调试菜单并持久化。
    func unlock() {
        isUnlocked = true
        defaults.set(true, forKey: Self.storageKey)
    }

    /// 重新隐藏调试菜单并持久化。
    func lock() {
        isUnlocked = false
        defaults.set(false, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: 跑测试确认通过(绿)**

Run REGEN, then TEST with `-only-testing:FreshPantryTests/DebugMenuGateTests`.
Expected: PASS(3 tests)。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/FreshPantry/Features/Debug/DebugMenuGate.swift apps/ios/FreshPantryTests/DebugMenuGateTests.swift
git commit -m "feat(ios): add DebugMenuGate (hidden debug-menu unlock state)"
```

---

### Task 4: 注入 AppDependencies

**Files:**
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift`(属性声明区 + init)

> 纯接线,无可独立单测的单元;验证 = 整个 target 编译 + 既有套件保持绿。

- [ ] **Step 1: 加属性声明**

在 `apps/ios/FreshPantry/App/AppDependencies.swift` 中,紧接 `appearanceStore` 声明(当前在 `let appearanceStore: AppearanceStore` 这一行,约 56 行)之后插入:

```swift
    /// UserDefaults-backed feature-flag 覆盖值(调试菜单)。设备本地,排除备份/同步。
    let featureFlagStore: FeatureFlagStore
    /// UserDefaults-backed 隐藏调试菜单解锁状态。设备本地,排除备份/同步。
    let debugMenuGate: DebugMenuGate
```

- [ ] **Step 2: 加 init 构建**

在 init 中,紧接 `self.appearanceStore = AppearanceStore()`(约 134 行)之后插入:

```swift
        self.featureFlagStore = FeatureFlagStore()
        self.debugMenuGate = DebugMenuGate()
```

- [ ] **Step 3: 编译验证**

Run REGEN, then BUILD ONLY(`build-for-testing`)。
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add apps/ios/FreshPantry/App/AppDependencies.swift
git commit -m "feat(ios): wire FeatureFlagStore + DebugMenuGate into AppDependencies"
```

---

### Task 5: DebugMenuView

**Files:**
- Create: `apps/ios/FreshPantry/Features/Debug/DebugMenuView.swift`

> SwiftUI 视图,仓库无视图单测基建;验证 = 编译,行为在 Task 6 后手动验。

- [ ] **Step 1: 实现 DebugMenuView**

Create `apps/ios/FreshPantry/Features/Debug/DebugMenuView.swift`:

```swift
import SwiftUI

/// 隐藏的「调试菜单」,由 Settings「版本」行连点 7 次解锁(见 `DebugMenuGate`)。
/// 把每个 `FeatureFlag` 列为绑定到共享 `FeatureFlagStore` 的开关,另加重置全部 /
/// 重新锁定。同 Settings 其余部分,从注入的 `AppDependencies` 读取 store。
struct DebugMenuView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let store = dependencies.featureFlagStore
        let gate = dependencies.debugMenuGate

        Form {
            Section {
                ForEach(FeatureFlag.allCases, id: \.self) { flag in
                    Toggle(isOn: Binding(
                        get: { store.isEnabled(flag) },
                        set: { store.set(flag, $0) }
                    )) {
                        VStack(alignment: .leading, spacing: FkSpacing.xs) {
                            Text(flag.title)
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Text(store.isOverridden(flag)
                                ? "\(flag.summary) · 已覆盖"
                                : "\(flag.summary) · 默认")
                                .font(.fkBodySmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                    }
                }
            } header: {
                Text("功能开关")
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)

            Section {
                Button("重置全部为默认") { store.resetAll() }
                    .foregroundStyle(Color.fkPrimary)
                Button(role: .destructive) { gate.lock() } label: {
                    Text("锁定调试菜单")
                }
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)
        }
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .tint(.fkPrimary)
        .navigationTitle("调试菜单")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: 编译验证**

Run REGEN, then BUILD ONLY。
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add apps/ios/FreshPantry/Features/Debug/DebugMenuView.swift
git commit -m "feat(ios): add DebugMenuView (feature-flag toggles)"
```

---

### Task 6: SettingsView 接线(连点解锁 + debugSection + demo 行)

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`

> `SettingsContent` 已持有 `@Environment(AppDependencies.self) private var dependencies`,直接读 `dependencies.debugMenuGate` / `dependencies.featureFlagStore`,无需改 `SettingsView → SettingsContent` 的 init 入参。

- [ ] **Step 1: 加版本连点计数 state**

在 `SettingsContent` 的 state 声明区,紧接 `@State private var showClearHistoryConfirm = false`(约 60 行)之后插入:

```swift
    /// 隐藏调试菜单的连点计数:累计点「版本」行 7 次解锁 `DebugMenuGate`。
    @State private var versionTapCount = 0
```

- [ ] **Step 2: 在 Form 里条件插入 debugSection**

把 `body` 的 `Form { ... }` 中这段(约 72-73 行):

```swift
            comingSoonSection
            aboutSection
```

改为:

```swift
            comingSoonSection
            if dependencies.debugMenuGate.isUnlocked {
                debugSection
            }
            aboutSection
```

- [ ] **Step 3: 改 aboutSection —— 版本行加连点手势 + demo 行**

把 `aboutSection`(约 436-460 行)整体替换为:

```swift
    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer()
                Text(AppVersion.displayString)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !dependencies.debugMenuGate.isUnlocked else { return }
                versionTapCount += 1
                if versionTapCount >= 7 {
                    dependencies.debugMenuGate.unlock()
                    versionTapCount = 0
                }
            }
            .sensoryFeedback(.success, trigger: dependencies.debugMenuGate.isUnlocked)
            if dependencies.featureFlagStore.isEnabled(.demoFeature) {
                HStack {
                    Text("🎉 示例功能已开启")
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurface)
                }
            }
            HStack {
                Text("开源致谢")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer()
                Text("HowToCook · Unlicense")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        } header: {
            Text("关于 \(AppVersion.appName)")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }
```

- [ ] **Step 4: 加 debugSection(放在 aboutSection 之前)**

在 `aboutSection` 的闭合 `}` 之后、`// MARK: - Rows`(约 461-463 行)之前,插入:

```swift
    // MARK: 调试

    /// 隐藏调试菜单入口:仅当 `DebugMenuGate.isUnlocked` 时由 `body` 条件渲染。
    private var debugSection: some View {
        Section {
            NavigationLink {
                DebugMenuView()
            } label: {
                SettingsLinkLabel(
                    systemImage: "ladybug.fill",
                    title: "调试菜单",
                    subtitle: "功能开关与实验项"
                )
            }
        } header: {
            Text("调试")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }
```

- [ ] **Step 5: 编译验证**

Run REGEN, then BUILD ONLY。
Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 提交**

```bash
git add apps/ios/FreshPantry/Features/Settings/SettingsView.swift
git commit -m "feat(ios): hidden debug menu unlock + demo flag row in Settings"
```

---

### Task 7: 全量验证

- [ ] **Step 1: 跑全套测试**

Run REGEN, then TEST(不带 `-only-testing`,跑整个 `FreshPantryTests`)。
Expected: 全绿,新增 11 个测试(2+6+3)随既有套件一起通过。

- [ ] **Step 2: 手动冒烟(模拟器)**

在 iOS 模拟器运行 app:
1. 进「设置」tab → 滚到底「关于」section。
2. 连点「版本」行 7 次 → 触感反馈,「调试」section 出现(内含「调试菜单」入口)。
3. 进「调试菜单」→ 打开「示例功能」开关(副标题变「… · 已覆盖」)。
4. 返回设置 → 「关于」section 即时出现「🎉 示例功能已开启」行(无需重启)。
5. 回「调试菜单」→「重置全部为默认」→ demo 行消失。
6. 「锁定调试菜单」→ 「调试」section 消失;杀进程重启,仍锁定。
7. 再解锁后杀进程重启 → 「调试」section 仍在(解锁已持久化)。

- [ ] **Step 3: 确认无遗留改动**

```bash
git status
```
Expected: 工作区干净(本计划相关改动已全部提交)。

---

## 自检(Self-Review)

**Spec coverage**(逐条对 spec):
- 纯本地 / 编译期默认 + UserDefaults 覆盖 → Task 1(默认)+ Task 2(覆盖)✅
- 隐藏调试菜单 + 连点 7 次解锁(运行期,非 `#if DEBUG`)→ Task 6 Step 3 ✅
- 仅布尔 flag → `FeatureFlag.defaultValue: Bool` + `FeatureFlagStore` 全布尔 ✅
- 解锁持久化 → Task 3(`debug_menu_unlocked_v1`)✅
- 设备本地、排除备份/同步 → 文档注释声明;不接 backup/sync(无对应代码改动)✅
- 示例 flag 端到端 → Task 6 demo 行 + Task 7 Step 2 手动链路 ✅
- 错误边界(persist 失败静默 / 防御 decode / 未知 key 忽略)→ Task 2 实现 + decode 测试 ✅
- 测试三套件 → Task 1/2/3 ✅
- XcodeGen 自动纳入 → 各 Task 的 REGEN 步骤 ✅

**Placeholder scan:** 无 TBD/TODO;所有代码步骤含完整可照抄代码。

**Type consistency:** `FeatureFlag`(case `demoFeature`,属性 `title`/`summary`/`defaultValue`)、`FeatureFlagStore`(`isEnabled`/`isOverridden`/`set`/`reset`/`resetAll`/`overrides`/`storageKey`/`decode`)、`DebugMenuGate`(`isUnlocked`/`unlock`/`lock`/`storageKey`)在测试、实现、视图、接线中签名一致。设计 token(`FkSpacing.xs`、`fkBodyMedium`/`fkBodySmall`、`fkOnSurface`/`fkOnSurfaceVariant`/`fkSurfaceContainerLowest`/`fkPrimary`/`fkSurface`、`SettingsLinkLabel(systemImage:title:subtitle:)`)均已对现有代码核实存在。
