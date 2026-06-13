# 诊断埋点(Diagnostics Telemetry)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 app 四个关键流程加诊断/可观测性埋点,失败/轨迹/耗时上报到已集成的 Sentry,本阶段(Phase 1)交付门面 + 同步流程埋点。

**Architecture:** 全 app 只对一个 `Diagnostics` 门面协议编程(`breadcrumb` / `failure` / 共享 `measure`)。三个实现按构建配置分流:DEBUG→OSLog、Release+配置→Sentry、否则→Noop,严格镜像现有 `SentryBootstrap` 的 `#if !DEBUG` 门控。门面通过 `AppDependencies` 注入到各 service,每个 service 构造器给 `Diagnostics = NoopDiagnostics()` 默认值,保证现有调用点与测试零改动。

**Tech Stack:** Swift 6(strict concurrency complete)、SwiftUI、Swift Testing(`@Test`/`#expect`)、sentry-cocoa 9.17、XcodeGen、SwiftData。spec:`docs/superpowers/specs/2026-06-13-diagnostics-telemetry-design.md`。

---

## 全局约定(每个 Task 通用)

**工作目录:** 所有 `xcodebuild` / `xcodegen` 命令在 `apps/ios/` 下执行;`git add` 用仓库根相对路径(`apps/ios/...`)。

**新增源文件后必须重新生成工程**(XcodeGen,路径 glob,`.xcodeproj` 已提交):

```bash
cd apps/ios && xcodegen generate
```

**运行测试(单套件):**

```bash
cd apps/ios
UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; c=[v for rt in d for v in d[rt] if v.get('isAvailable') and v['name'].startswith('iPhone')]; print(c[0]['udid'] if c else '')")
xcodebuild test -project FreshPantry.xcodeproj -scheme FreshPantry \
  -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:FreshPantryTests/<套件名> 2>&1 | tail -40
```

**运行全量测试:** 去掉 `-only-testing` 行。

**事件命名:** `<domain>.<op>[.<detail>]` 稳定 dotted id(`sync.push`、`sync.deadletter`)。

**tags 隐私硬规则:** 只放低基数、非内容维度(`entityType`/`errorClass`/`source`/`outcome`/`phase`/`count`);**绝不**放食材名、邮箱、原始条码、明文 id;`durationMs` 只进 breadcrumb,**绝不**进 Sentry tag(高基数)。

**测试构建注意:** 测试跑在 Debug + 模拟器,`SentryDiagnostics` 被 `#if !DEBUG` 排除、不参与编译;测试用 `SpyDiagnostics` 直接注入,或工厂返回 `OSLogDiagnostics`。

---

## File Structure(Phase 1)

**新建:**

- `apps/ios/FreshPantry/Services/Diagnostics/Diagnostics.swift` — 协议 + `measure` 默认实现 + `diagnosticErrorClass` 帮助函数 + `NoopDiagnostics`(平凡 struct,与协议同文件)。
- `apps/ios/FreshPantry/Services/Diagnostics/OSLogDiagnostics.swift` — `os.Logger` 实现(DEBUG 本地可见)。
- `apps/ios/FreshPantry/Services/Diagnostics/SentryDiagnostics.swift` — Sentry 实现,整文件 `#if !DEBUG` 包裹。
- `apps/ios/FreshPantry/Services/Diagnostics/DiagnosticsFactory.swift` — 按构建配置建实现。
- `apps/ios/FreshPantryTests/Diagnostics/SpyDiagnostics.swift` — 测试替身(记录所有调用)。
- `apps/ios/FreshPantryTests/Diagnostics/DiagnosticsMeasureTests.swift` — `measure` 默认实现单测。
- `apps/ios/FreshPantryTests/Diagnostics/SyncCoordinatorDiagnosticsTests.swift` — 同步接缝事件断言。

**修改:**

- `apps/ios/FreshPantry/App/AppDependencies.swift` — 加 `diagnostics` 属性 + 工厂建一次 + 注入三个同步 service。
- `apps/ios/FreshPantry/Sync/SyncCoordinator.swift` — 加 `diagnostics` 参数 + 埋 strike/deadletter/partial_ack/ack_removal/cleared。
- `apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift` — 加 `diagnostics` 参数 + 埋 push 失败/冲突/批次(构建验证)。
- `apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift` — 加 `diagnostics` 参数 + 埋 pull/delta/migrate 失败(构建验证)。

---

## Task 1: Diagnostics 门面协议 + measure 默认 + Noop

**Files:**
- Create: `apps/ios/FreshPantry/Services/Diagnostics/Diagnostics.swift`

- [ ] **Step 1: 写门面文件**

```swift
import Foundation

/// 所有被埋点接缝唯一编程对象的诊断门面。三个原语;`measure` 是共享默认实现
/// (见下),所以具体 sink 只需实现 `breadcrumb` + `failure`。
///
/// 不变量:任何方法都不得因自身逻辑抛错、不得影响 app 行为。`measure` 仅透传
/// (rethrow)被包裹 `work` 的错误;`breadcrumb`/`failure` 内部吞掉一切。诊断的
/// bug 绝不能搞挂功能。
protocol Diagnostics: Sendable {
    /// 操作轨迹 —— 留一条 Sentry breadcrumb,本身从不上报。`tags` 为低基数、
    /// 非 PII 维度(entityType、source、outcome…)。
    func breadcrumb(_ name: String, _ tags: [String: String])

    /// 一次失败 → 一条 Sentry 事件(level=.error),按 `name` + 错误类名做
    /// fingerprint,使同一失败聚合成一个 issue。`error` 对从未 throw 的逻辑
    /// 失败(如同步 strike)为 nil。
    func failure(_ name: String, error: Error?, _ tags: [String: String])
}

extension Diagnostics {
    /// 给一次异步操作计时:先发 `<name>.start` breadcrumb,成功则发 `<name>`
    /// breadcrumb 带 `outcome=ok` + `durationMs`,失败则发 `failure(<name>)` 带
    /// `outcome=fail` + `errorClass`(耗时进 breadcrumb,绝不进 Sentry tag —— 高
    /// 基数)。透明 rethrow 底层错误。
    func measure<T>(
        _ name: String,
        _ tags: [String: String] = [:],
        _ work: () async throws -> T
    ) async throws -> T {
        let clock = ContinuousClock()
        let started = clock.now
        breadcrumb("\(name).start", tags)
        do {
            let result = try await work()
            var ok = tags
            ok["outcome"] = "ok"
            ok["durationMs"] = Self.millis(from: started, clock: clock)
            breadcrumb(name, ok)
            return result
        } catch {
            var failed = tags
            failed["outcome"] = "fail"
            failed["errorClass"] = diagnosticErrorClass(error)
            var crumb = failed
            crumb["durationMs"] = Self.millis(from: started, clock: clock)
            breadcrumb(name, crumb)
            failure(name, error: error, failed)
            throw error
        }
    }

    /// 自 `started` 起的毫秒数,经 `Duration.components` 计算(避免 `Duration`
    /// 相除的不确定性)。
    private static func millis(from started: ContinuousClock.Instant, clock: ContinuousClock) -> String {
        let comps = (clock.now - started).components
        let ms = comps.seconds * 1000 + comps.attoseconds / 1_000_000_000_000_000
        return String(ms)
    }
}

/// 错误的类型名 —— 一个可安全用作 Sentry tag 的低基数类别标签(原始错误
/// message 可能含用户数据,从不用作 tag)。
func diagnosticErrorClass(_ error: Error) -> String {
    String(describing: type(of: error))
}

/// 默认 sink:什么都不做。所有 service 构造器的默认值,保证未接线的代码路径
/// 与全部现有测试行为完全不变。`measure` 由协议扩展提供(仍正确计时并透传)。
struct NoopDiagnostics: Diagnostics {
    func breadcrumb(_ name: String, _ tags: [String: String]) {}
    func failure(_ name: String, error: Error?, _ tags: [String: String]) {}
}
```

- [ ] **Step 2: 重新生成工程**

Run: `cd apps/ios && xcodegen generate`
Expected: 成功,无报错。

- [ ] **Step 3: 编译验证(仅构建,不跑测试)**

Run:
```bash
cd apps/ios
UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; c=[v for rt in d for v in d[rt] if v.get('isAvailable') and v['name'].startswith('iPhone')]; print(c[0]['udid'] if c else '')")
xcodebuild build-for-testing -project FreshPantry.xcodeproj -scheme FreshPantry -destination "platform=iOS Simulator,id=$UDID" 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`(strict concurrency 下 `NoopDiagnostics` 为无状态 struct,自动 `Sendable`)。

- [ ] **Step 4: 提交**

```bash
git add apps/ios/FreshPantry/Services/Diagnostics/Diagnostics.swift apps/ios/FreshPantry.xcodeproj
git commit -m "feat(diagnostics): Diagnostics 门面协议 + measure 默认 + Noop"
```

---

## Task 2: SpyDiagnostics 测试替身 + measure 单测

**Files:**
- Create: `apps/ios/FreshPantryTests/Diagnostics/SpyDiagnostics.swift`
- Create: `apps/ios/FreshPantryTests/Diagnostics/DiagnosticsMeasureTests.swift`

- [ ] **Step 1: 写 SpyDiagnostics 替身**

```swift
import Foundation
@testable import FreshPantry

/// 记录每次诊断调用以供断言。线程安全(`breadcrumb`/`failure` 从 actor 上下文
/// 触发),用锁保护缓冲区 —— 同 `AuthServiceTests.FakeBackend` 的 `@unchecked
/// Sendable` 模式。
final class SpyDiagnostics: Diagnostics, @unchecked Sendable {
    struct Call: Equatable {
        let name: String
        let tags: [String: String]
        /// 失败调用的错误类名;breadcrumb / nil-error 失败为 nil。
        let errorClass: String?
    }

    private let lock = NSLock()
    private var _breadcrumbs: [Call] = []
    private var _failures: [Call] = []

    var breadcrumbs: [Call] { lock.withLock { _breadcrumbs } }
    var failures: [Call] { lock.withLock { _failures } }
    var breadcrumbNames: [String] { breadcrumbs.map(\.name) }
    var failureNames: [String] { failures.map(\.name) }

    func breadcrumb(_ name: String, _ tags: [String: String]) {
        lock.withLock { _breadcrumbs.append(Call(name: name, tags: tags, errorClass: nil)) }
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let klass = error.map(diagnosticErrorClass)
        lock.withLock { _failures.append(Call(name: name, tags: tags, errorClass: klass)) }
    }
}
```

- [ ] **Step 2: 写 measure 失败测试(先失败)**

```swift
import Foundation
import Testing
@testable import FreshPantry

/// `Diagnostics.measure` 默认实现的行为:成功/失败两路各发什么、是否透传错误。
struct DiagnosticsMeasureTests {
    private struct Boom: Error {}

    @Test func measureSuccessEmitsStartAndOkBreadcrumbs() async throws {
        let spy = SpyDiagnostics()
        let value = try await spy.measure("scan.lookup", ["source": "off"]) { 42 }

        #expect(value == 42)
        #expect(spy.breadcrumbNames == ["scan.lookup.start", "scan.lookup"])
        #expect(spy.failures.isEmpty)
        let ok = spy.breadcrumbs.last!
        #expect(ok.tags["outcome"] == "ok")
        #expect(ok.tags["source"] == "off")
        #expect(ok.tags["durationMs"] != nil)
    }

    @Test func measureFailureRethrowsAndRecordsFailure() async {
        let spy = SpyDiagnostics()
        await #expect(throws: Boom.self) {
            try await spy.measure("scan.lookup", ["source": "off"]) { throw Boom() }
        }

        // 失败路径:start + 一条带 outcome=fail 的 breadcrumb,外加一条 failure。
        #expect(spy.breadcrumbNames == ["scan.lookup.start", "scan.lookup"])
        #expect(spy.failureNames == ["scan.lookup"])
        let f = spy.failures.first!
        #expect(f.tags["outcome"] == "fail")
        #expect(f.tags["errorClass"] == "Boom")
        #expect(f.errorClass == "Boom")
    }
}
```

- [ ] **Step 3: 重新生成 + 跑测试,确认通过**

Run: `cd apps/ios && xcodegen generate`,然后跑 `-only-testing:FreshPantryTests/DiagnosticsMeasureTests`(命令见全局约定)。
Expected: 两个测试 PASS(`measure` 已由 Task 1 的协议扩展实现 —— 这是验证而非 TDD 红灯;若失败说明扩展逻辑有 bug,回 Task 1 修)。

- [ ] **Step 4: 提交**

```bash
git add apps/ios/FreshPantryTests/Diagnostics/ apps/ios/FreshPantry.xcodeproj
git commit -m "test(diagnostics): SpyDiagnostics 替身 + measure 默认实现单测"
```

---

## Task 3: OSLogDiagnostics(DEBUG 本地可见)

**Files:**
- Create: `apps/ios/FreshPantry/Services/Diagnostics/OSLogDiagnostics.swift`

- [ ] **Step 1: 写实现**

```swift
import Foundation
import os

/// 把诊断打到系统统一日志(subsystem `com.kunish.freshPantry`,category
/// `diagnostics`),开发期本地可见。DEBUG 工厂的默认 sink —— 永不进 Sentry,
/// 与 `SentryBootstrap` 在 DEBUG 整体禁用 Sentry 一致。
struct OSLogDiagnostics: Diagnostics {
    private static let logger = Logger(subsystem: "com.kunish.freshPantry", category: "diagnostics")

    func breadcrumb(_ name: String, _ tags: [String: String]) {
        Self.logger.debug("📊 \(name, privacy: .public) \(Self.format(tags), privacy: .public)")
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let err = error.map { String(describing: $0) } ?? "-"
        Self.logger.error(
            "❌ \(name, privacy: .public) \(Self.format(tags), privacy: .public) err=\(err, privacy: .public)"
        )
    }

    private static func format(_ tags: [String: String]) -> String {
        tags.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
```

- [ ] **Step 2: 重新生成 + 编译验证**

Run: `cd apps/ios && xcodegen generate`,然后 `build-for-testing`(命令见 Task 1 Step 3)。
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 提交**

```bash
git add apps/ios/FreshPantry/Services/Diagnostics/OSLogDiagnostics.swift apps/ios/FreshPantry.xcodeproj
git commit -m "feat(diagnostics): OSLogDiagnostics(DEBUG 本地可见 sink)"
```

---

## Task 4: SentryDiagnostics(#if !DEBUG)

**Files:**
- Create: `apps/ios/FreshPantry/Services/Diagnostics/SentryDiagnostics.swift`

- [ ] **Step 1: 写实现(整文件 `#if !DEBUG` 包裹)**

```swift
#if !DEBUG
import Foundation
import Sentry

/// 把诊断路由到 Sentry。仅在非 DEBUG 构建编译(与 `SentryBootstrap` 一致 ——
/// 它同样 `#if !DEBUG` 包裹每个 Sentry 调用)。假定 `SentryBootstrap.start` 已
/// 启动 SDK;若未启动,这些调用在 sentry-cocoa 内部是无害 no-op。
///
/// API 形态(sentry-cocoa 9.17):`Breadcrumb(level:category:)` + `.message`/
/// `.data`、`SentrySDK.addBreadcrumb`、`SentrySDK.capture(error:block:)` 带
/// `Scope.setTag`/`fingerprint`、`Event(level:)` + `SentryMessage(formatted:)` +
/// `.tags`/`.fingerprint` + `SentrySDK.capture(event:)`。
struct SentryDiagnostics: Diagnostics {
    func breadcrumb(_ name: String, _ tags: [String: String]) {
        let crumb = Breadcrumb(level: .info, category: "diagnostic")
        crumb.message = name
        if !tags.isEmpty { crumb.data = tags }
        SentrySDK.addBreadcrumb(crumb)
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let fingerprintClass = tags["errorClass"] ?? error.map(diagnosticErrorClass) ?? "logic"
        if let error {
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: name, key: "diagnostic")
                for (key, value) in tags { scope.setTag(value: value, key: key) }
                scope.fingerprint = [name, fingerprintClass]
            }
        } else {
            let event = Event(level: .error)
            event.message = SentryMessage(formatted: name)
            var merged = tags
            merged["diagnostic"] = name
            event.tags = merged
            event.fingerprint = [name, fingerprintClass]
            SentrySDK.capture(event: event)
        }
    }
}
#endif
```

- [ ] **Step 2: 重新生成 + 非 DEBUG 编译验证**

`#if !DEBUG` 内容在 Debug 模拟器构建里被排除,因此 `build-for-testing`(Debug)不会编译它。用 Release 构建验证这段真的能编译:

Run:
```bash
cd apps/ios
xcodebuild build -project FreshPantry.xcodeproj -scheme FreshPantry \
  -configuration Release -destination "generic/platform=iOS" \
  -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`。若签名导致失败(本地无证书),改加 `CODE_SIGNING_ALLOWED=NO`:
```bash
xcodebuild build -project FreshPantry.xcodeproj -scheme FreshPantry \
  -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO 2>&1 | tail -25
```
重点确认无 sentry-cocoa API 不匹配的编译错误(若有,按 9.17 实际签名微调 `Breadcrumb`/`Event`/`capture` 调用)。

- [ ] **Step 3: 提交**

```bash
git add apps/ios/FreshPantry/Services/Diagnostics/SentryDiagnostics.swift
git commit -m "feat(diagnostics): SentryDiagnostics(#if !DEBUG 的 Sentry sink)"
```

---

## Task 5: DiagnosticsFactory

**Files:**
- Create: `apps/ios/FreshPantry/Services/Diagnostics/DiagnosticsFactory.swift`

- [ ] **Step 1: 写工厂**

```swift
import Foundation

/// 按构建配置建对应 sink,门控逻辑刻意镜像 `SentryBootstrap.start`:
/// - DEBUG → OSLog(永不碰 Sentry)
/// - Release + 有 Sentry 配置 → Sentry
/// - Release + 无配置(OSS checkout / 空 Secrets)→ Noop
enum DiagnosticsFactory {
    static func make(sentryConfig: SentryConfig?) -> Diagnostics {
        #if DEBUG
        return OSLogDiagnostics()
        #else
        return sentryConfig == nil ? NoopDiagnostics() : SentryDiagnostics()
        #endif
    }
}
```

- [ ] **Step 2: 重新生成 + 编译验证**

Run: `cd apps/ios && xcodegen generate`,然后 `build-for-testing`(Task 1 Step 3 命令)。
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 提交**

```bash
git add apps/ios/FreshPantry/Services/Diagnostics/DiagnosticsFactory.swift apps/ios/FreshPantry.xcodeproj
git commit -m "feat(diagnostics): DiagnosticsFactory(按构建配置分流 sink)"
```

---

## Task 6: 接入 AppDependencies(DI)

**Files:**
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift`

- [ ] **Step 1: 加 `diagnostics` 属性声明**

在 `notificationCoordinator` 属性声明之后(约 `apps/ios/FreshPantry/App/AppDependencies.swift:106`)加:

```swift
    /// 诊断/可观测性门面。按构建配置分流(DEBUG→OSLog、Release+配置→Sentry、
    /// 否则→Noop)。注入到同步等关键 service;未注入处用 NoopDiagnostics 默认值。
    let diagnostics: Diagnostics
```

- [ ] **Step 2: 在 init 里建实例(在建 `clientProvider` 之前)**

在 `init` 中 `let clientProvider = SupabaseClientProvider(config: config)`(约 `:155`)那行**之前**插入:

```swift
        let diagnostics = DiagnosticsFactory.make(sentryConfig: config?.sentry)
        self.diagnostics = diagnostics
```

- [ ] **Step 3: 把 diagnostics 传给三个同步 service**

在同一 `init` 的 `if let client = clientProvider.client {` 分支里,改这三处构造调用(`apps/ios/FreshPantry/App/AppDependencies.swift:171-190` 区域),各加 `diagnostics:` 实参:

```swift
            let gateway = SupabaseSyncGateway(client: client, diagnostics: diagnostics)
            let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, diagnostics: diagnostics)
```

以及 `householdContentSync` 构造的末尾参数加上 `diagnostics`:

```swift
            self.householdContentSync = HouseholdContentSyncCoordinator(
                remote: remoteRepository,
                push: coordinator,
                outbox: outbox,
                inventory: self.inventoryRepository,
                shopping: self.shoppingRepository,
                customRecipe: self.customRecipeRepository,
                mealPlan: self.mealPlanRepository,
                foodLog: self.foodLogRepository,
                session: session,
                diagnostics: diagnostics
            )
```

(`SyncWriter` 与 local-only 分支不传 —— 它们不在 Phase 1 埋点范围,用各自默认值。)

- [ ] **Step 4: 编译验证**

此刻 `SyncCoordinator`/`SupabaseSyncGateway`/`HouseholdContentSyncCoordinator` 还没有 `diagnostics:` 参数,**预期编译失败**(下面 Task 7-9 给它们加参数后才绿)。

Run: `build-for-testing`(Task 1 Step 3 命令)。
Expected: FAIL —— 报这三个构造器没有 `diagnostics` 标签的实参。这是预期的;**先不提交**,继续 Task 7。

> 说明:Task 6-9 是一组耦合改动,在 Task 9 末尾一次性编译通过并提交。这样避免中途留下不可编译的提交。

---

## Task 7: SyncCoordinator 埋点 + 测试

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/SyncCoordinator.swift`
- Create: `apps/ios/FreshPantryTests/Diagnostics/SyncCoordinatorDiagnosticsTests.swift`

- [ ] **Step 1: 先写失败测试**

```swift
import Foundation
import Testing
@testable import FreshPantry

/// 验证 SyncCoordinator 在失败路径上发出正确的诊断事件,经 SpyDiagnostics 断言。
/// 复用本套件内的 fake outbox/gateway(与 SyncCoordinatorTests 同款最小实现)。
struct SyncCoordinatorDiagnosticsTests {
    private struct ValidationError: Error {}

    private func operation(id: String, entityId: String = "ing_1") -> SyncOperation {
        SyncOperation(
            id: id, householdId: "home", entityType: .inventoryItem,
            entityId: entityId, operation: .create, patch: [:],
            clientId: "client", createdAt: Date(timeIntervalSince1970: 1000)
        )
    }

    private actor FakeOutbox: OutboxReading {
        private var pending: [SyncOperation]
        init(pending: [SyncOperation]) { self.pending = pending }
        func loadPending() async throws -> [SyncOperation] { pending }
        func removeAcknowledged(_ ids: Set<String>) async throws {
            pending.removeAll { ids.contains($0.id) }
        }
    }

    private actor FakeGateway: RemoteSyncGateway {
        enum Outcome: Sendable { case acknowledge(Set<String>); case fail(any Error) }
        private var script: [Outcome]
        init(script: [Outcome]) { self.script = script }
        func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String> {
            let outcome = script.isEmpty ? Outcome.acknowledge([]) : script.removeFirst()
            switch outcome {
            case .acknowledge(let ids): return ids
            case .fail(let error): throw error
            }
        }
    }

    @Test func deadLetterQuarantineEmitsFailureEvent() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        // 永久错误连续 3 次 → 第 3 次命中阈值 → 隔离。
        let gateway = FakeGateway(script: [
            .fail(ValidationError()), .fail(ValidationError()), .fail(ValidationError()),
        ])
        let spy = SpyDiagnostics()
        let coordinator = SyncCoordinator(
            outbox: outbox, remote: gateway, deadLetterThreshold: 3, diagnostics: spy)

        await coordinator.pushPending() // strike 1 → breadcrumb count=1
        await coordinator.pushPending() // strike 2 → breadcrumb count=2
        await coordinator.pushPending() // strike 3 → 隔离 → failure

        #expect(spy.failureNames.contains("sync.deadletter"))
        let dead = spy.failures.first { $0.name == "sync.deadletter" }!
        #expect(dead.tags["entityType"] == "inventory_item")
        #expect(dead.errorClass == nil) // 逻辑失败,无 throw
        #expect(spy.breadcrumbs.filter { $0.name == "sync.push.strike" }.count == 2)
    }

    @Test func partialAckEmitsBreadcrumb() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1"), operation(id: "op_2", entityId: "ing_2")])
        // 只 ack op_1 → op_2 是静默部分失败(在线默认 true → strike op_2)。
        let gateway = FakeGateway(script: [.acknowledge(["op_1"])])
        let spy = SpyDiagnostics()
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, diagnostics: spy)

        await coordinator.pushPending()

        #expect(spy.breadcrumbNames.contains("sync.partial_ack"))
        let crumb = spy.breadcrumbs.first { $0.name == "sync.partial_ack" }!
        #expect(crumb.tags["entityType"] == "inventory_item")
    }

    @Test func clearDeadLettersEmitsBreadcrumb() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        let gateway = FakeGateway(script: [
            .fail(ValidationError()), .fail(ValidationError()), .fail(ValidationError()),
        ])
        let spy = SpyDiagnostics()
        let coordinator = SyncCoordinator(
            outbox: outbox, remote: gateway, deadLetterThreshold: 3, diagnostics: spy)
        await coordinator.pushPending()
        await coordinator.pushPending()
        await coordinator.pushPending()

        await coordinator.clearDeadLetters()

        #expect(spy.breadcrumbNames.contains("sync.deadletter.cleared"))
        #expect(spy.breadcrumbs.first { $0.name == "sync.deadletter.cleared" }!.tags["count"] == "1")
    }
}
```

- [ ] **Step 2: 给 SyncCoordinator 加 `diagnostics` 参数**

改 `apps/ios/FreshPantry/Sync/SyncCoordinator.swift`。在属性区(约 `:41` `private let retry` 之后)加:

```swift
    private let diagnostics: Diagnostics
```

改 `init`(`:96-106`)签名与体,加带默认值的 `diagnostics`:

```swift
    init(
        outbox: OutboxReading,
        remote: RemoteSyncGateway,
        retry: SyncRetryPolicy = SyncRetryPolicy(),
        deadLetterThreshold: Int = 3,
        diagnostics: Diagnostics = NoopDiagnostics()
    ) {
        self.outbox = outbox
        self.remote = remote
        self.retry = retry
        self.deadLetterThreshold = deadLetterThreshold
        self.diagnostics = diagnostics
    }
```

- [ ] **Step 3: 埋 partial_ack(在 `pushOnce` 的部分-ack 分支)**

`apps/ios/FreshPantry/Sync/SyncCoordinator.swift:279-283`,在 `strike(failed, pending: pending)` 之前加一行 breadcrumb:

```swift
            if acknowledged.count < active.count,
               let failed = active.first(where: { !acknowledged.contains($0.id) }),
               isOnline {
                diagnostics.breadcrumb("sync.partial_ack", ["entityType": failed.entityType.rawValue])
                strike(failed, pending: pending)
            }
```

- [ ] **Step 4: 埋 ack_removal 失败(在 `removeAcknowledged` 的 catch)**

`apps/ios/FreshPantry/Sync/SyncCoordinator.swift:265-269`,在现有 `Self.logger.error(...)` 之后加:

```swift
            } catch {
                Self.logger.error(
                    "outbox removeAcknowledged failed (retried next run): \(String(describing: error), privacy: .public)"
                )
                diagnostics.failure("sync.ack_removal", error: error, [:])
            }
```

- [ ] **Step 5: 埋 strike + deadletter(在 `strike` 方法)**

替换 `apps/ios/FreshPantry/Sync/SyncCoordinator.swift:300-310` 的 `strike` 方法体为:

```swift
    private func strike(_ op: SyncOperation, pending: [SyncOperation]) {
        let key = EntityKey(op)
        let count = (headFailureCounts[key] ?? 0) + 1
        guard count >= deadLetterThreshold else {
            headFailureCounts[key] = count
            diagnostics.breadcrumb(
                "sync.push.strike",
                ["entityType": op.entityType.rawValue, "count": String(count)]
            )
            return
        }
        headFailureCounts[key] = nil
        deadLetteredEntities.insert(key)
        quarantinedOpIds.formUnion(pending.filter { EntityKey($0) == key }.map(\.id))
        diagnostics.failure("sync.deadletter", error: nil, ["entityType": op.entityType.rawValue])
    }
```

- [ ] **Step 6: 埋 cleared(在 `clearDeadLetters`)**

替换 `apps/ios/FreshPantry/Sync/SyncCoordinator.swift:150-155` 的 `clearDeadLetters` 为:

```swift
    func clearDeadLetters() async {
        let ids = quarantinedOpIds
        guard !ids.isEmpty else { return }
        diagnostics.breadcrumb("sync.deadletter.cleared", ["count": String(ids.count)])
        resetQuarantine()
        try? await outbox.removeAcknowledged(ids)
    }
```

- [ ] **Step 7: 重新生成(测试新文件)**

Run: `cd apps/ios && xcodegen generate`
Expected: 成功。(整体编译要等 Task 8-9 补完另两个 service 的参数,见下。)

---

## Task 8: SupabaseSyncGateway 埋点(构建验证)

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift`

> 该 gateway 现无单测(需 Supabase SDK),其埋点在已有日志接缝上加 2-3 行,由整体构建验证。

- [ ] **Step 1: 加 `diagnostics` 参数**

`apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift:28-34`,属性 + init:

```swift
    private let client: SupabaseClient
    private let diagnostics: Diagnostics
    private static let maxConflictRetries = 3
    private static let logger = Logger(subsystem: "com.kunish.freshPantry", category: "sync")

    init(client: SupabaseClient, diagnostics: Diagnostics = NoopDiagnostics()) {
        self.client = client
        self.diagnostics = diagnostics
    }
```

- [ ] **Step 2: 埋批次 breadcrumb(在 `pushOperations` 开头)**

`apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift:42-43`:

```swift
    func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String> {
        diagnostics.breadcrumb("sync.push_batch", ["count": String(ops.count)])
        var acknowledged: Set<String> = []
```

- [ ] **Step 3: 埋 push 失败(在 `reportPushError`)—— 捕获当前被吞掉的错误类型**

替换 `apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift:307-311` 的 `reportPushError`:

```swift
    private func reportPushError(_ op: SyncOperation, _ error: Error) {
        Self.logger.error(
            "push failed \(op.entityType.rawValue, privacy: .public)/\(op.operation.rawValue, privacy: .public) id=\(op.id, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        diagnostics.failure("sync.push", error: error, [
            "entityType": op.entityType.rawValue,
            "operation": op.operation.rawValue,
        ])
    }
```

- [ ] **Step 4: 埋冲突 breadcrumb(在 `reportConflict`)**

替换 `apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift:313-317` 的 `reportConflict`:

```swift
    private func reportConflict(_ op: SyncOperation, fields: [String]) {
        Self.logger.notice(
            "conflict resolved (client wins) \(op.entityType.rawValue, privacy: .public) id=\(op.entityId, privacy: .public) fields=\(fields.joined(separator: ","), privacy: .public)"
        )
        diagnostics.breadcrumb("sync.conflict", [
            "entityType": op.entityType.rawValue,
            "fieldCount": String(fields.count),
        ])
    }
```

> 注:用 `fieldCount`(数量)而非字段名拼接,避免字段名进 breadcrumb 抬高基数 / 泄露 schema 细节。

---

## Task 9: HouseholdContentSyncCoordinator 埋点 + 整体编译/测试

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift`

> 该 coordinator 现无直接单测(需真实 repo + RemotePantryRepository),其埋点在已有 catch 接缝上加行,由整体构建 + 现有同步集成测试验证。

- [ ] **Step 1: 加 `diagnostics` 参数**

`apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift:26-27`,属性区加(在 `session` 之后):

```swift
    private let session: SyncSession
    private let diagnostics: Diagnostics
```

`init`(`:46-66`)末尾参数 + 赋值:

```swift
    init(
        remote: RemotePantryRepository,
        push: SyncCoordinator,
        outbox: SyncOutboxRepository,
        inventory: InventoryRepository,
        shopping: ShoppingRepository,
        customRecipe: CustomRecipeRepository,
        mealPlan: MealPlanRepository,
        foodLog: FoodLogRepository,
        session: SyncSession,
        diagnostics: Diagnostics = NoopDiagnostics()
    ) {
        self.remote = remote
        self.push = push
        self.outbox = outbox
        self.inventory = inventory
        self.shopping = shopping
        self.customRecipe = customRecipe
        self.mealPlan = mealPlan
        self.foodLog = foodLog
        self.session = session
        self.diagnostics = diagnostics
    }
```

- [ ] **Step 2: 埋 delta 失败(在 `refreshDelta` 的 catch)**

`apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift:139-142`:

```swift
        } catch is CancellationError {
        } catch {
            Self.logger.error("while refreshing household delta: \(error.localizedDescription, privacy: .public)")
            diagnostics.failure("sync.pull", error: error, ["phase": "delta"])
        }
```

- [ ] **Step 3: 埋 migrate 失败(在 `startSync` 的 migrate catch)**

`apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift:164-168`:

```swift
            do {
                try await foodLog.migrateLegacyIds()
            } catch {
                Self.logger.error("FoodLog id migration failed: \(error.localizedDescription, privacy: .public)")
                diagnostics.failure("sync.migrate", error: error, [:])
            }
```

- [ ] **Step 4: 埋 startSync 成功 + 失败**

`apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift:219-234`,在成功收尾(cursor 推进后)与 catch 各加一行。把这段:

```swift
            if let advanced {
                await MainActor.run { session.setSyncCursor(advanced, for: householdId) }
            }
        } catch is CancellationError {
            // A household switch / stop cancelled this run — not an error.
        } catch {
            Self.logger.error("while syncing household content: \(error.localizedDescription, privacy: .public)")
```

改为:

```swift
            if let advanced {
                await MainActor.run { session.setSyncCursor(advanced, for: householdId) }
            }
            diagnostics.breadcrumb("sync.pull", ["outcome": "ok", "mode": since == nil ? "full" : "delta"])
        } catch is CancellationError {
            // A household switch / stop cancelled this run — not an error.
        } catch {
            Self.logger.error("while syncing household content: \(error.localizedDescription, privacy: .public)")
            diagnostics.failure("sync.pull", error: error, ["phase": "startSync"])
```

- [ ] **Step 5: 整体重新生成 + 编译(Task 6-9 闭环)**

Run: `cd apps/ios && xcodegen generate`,然后 `build-for-testing`(Task 1 Step 3 命令)。
Expected: `** BUILD SUCCEEDED **`(此刻三个 service 都有 `diagnostics` 参数,Task 6 的 DI 接线编译通过)。

- [ ] **Step 6: 跑诊断相关套件**

Run: `-only-testing:FreshPantryTests/SyncCoordinatorDiagnosticsTests` 与 `-only-testing:FreshPantryTests/DiagnosticsMeasureTests`(命令见全局约定)。
Expected: 全部 PASS。

- [ ] **Step 7: 提交 Task 6-9 闭环**

```bash
git add apps/ios/FreshPantry/App/AppDependencies.swift \
        apps/ios/FreshPantry/Sync/SyncCoordinator.swift \
        apps/ios/FreshPantry/Sync/SupabaseSyncGateway.swift \
        apps/ios/FreshPantry/Sync/HouseholdContentSyncCoordinator.swift \
        apps/ios/FreshPantryTests/Diagnostics/SyncCoordinatorDiagnosticsTests.swift \
        apps/ios/FreshPantry.xcodeproj
git commit -m "feat(diagnostics): 同步流程埋点 + AppDependencies DI 接线"
```

---

## Task 10: 全量回归 + Phase 1 收尾

- [ ] **Step 1: 跑全量测试套件**

Run: 全局约定的全量命令(去掉 `-only-testing`)。
Expected: 全绿(现有 669 测试 + 新增诊断测试)。零回归 —— 未接线路径仍走 `NoopDiagnostics` 默认值。

- [ ] **Step 2: 确认无未提交改动**

Run: `git status --short -- apps/ios/`
Expected: 干净(诊断相关改动都已提交;工作区其它 recipe-pipeline 改动不在本任务范围,勿动)。

- [ ] **Step 3(可选): 真机/Release 烟雾验证**

在 Release 构建里触发一次同步失败(如断网下做一次会进 outbox 的写入,再恢复),到 Sentry 后台确认出现 `sync.*` 事件分组。此步需发版环境,可留到下次 TestFlight 验证一并做。

---

## Phases 2-4 路线图(增量,各自单独细化为 bite-sized 任务)

> 以下三阶段沿用同一门面与 DI 模式(给目标 service 加 `diagnostics: Diagnostics = NoopDiagnostics()` 参数 + 在 `AppDependencies` 注入 + 在失败/成功接缝调用 + SpyDiagnostics 断言)。开始某阶段时,按 Phase 1 的 Task 模板把它展开为带完整代码的 bite-sized 步骤。**落地前必 grep 真实代码确认接缝未变。**

**Phase 2 — 登录/认证**(`Features/Auth/AuthService.swift`)
- 给 `AuthService.run(_:)` 加 `name` 参数,中央 catch 调 `diagnostics.failure(name, error:, ["errorClass": …])`;`sendCode`→`"auth.send_code"`、`verify`→`"auth.verify"`。
- 成功转移留痕:`auth.code_sent`/`auth.signed_in`/`auth.restore`/`auth.signout`。
- 隐私:邮箱是 PII → 只打布尔 `had_email`,不打邮箱本身。
- 测试:`AuthServiceTests` 注入 SpyDiagnostics,断言失败路径发 `auth.verify` failure、成功路径发对应 breadcrumb。

**Phase 3 — 扫码/营养/入库**(`Services/FoodDetailsClient.swift` 的 `OpenFoodFactsDetailsClient`、`Features/Inventory/AddIngredientView.swift`)
- OFF 查询用 `measure("scan.off_lookup", …)` 包裹(成功率 + 延迟,外部网络)。
- 营养解析失败 → `failure("scan.nutrition_parse", …)`;条码解析来源 → `breadcrumb("scan.resolve", ["source": "local"/"off"/"manual"])`;入库 → `breadcrumb("scan.intake", …)`。
- 隐私:不打原始条码 / 食材名。

**Phase 4 — 做菜扣减 + 备份**(`Features/Recipes/DeductionController.swift`、`Services/BackupService.swift`)
- 扣减应用 → `cook.deduct`(measure)、food-log 自动写失败 → `cook.foodlog`。
- 备份 → `backup.export`/`backup.import`/`backup.restore`(measure,失败必捕获;数据正确性关键)。

---

## Self-Review(对照 spec)

**1. Spec 覆盖:**
- 门面 3 原语(§2.1)→ Task 1。✅
- 三实现 + DEBUG 门控(§2.2)→ Task 1(Noop)/3(OSLog)/4(Sentry)。✅
- 工厂(§2.2)→ Task 5。✅
- DI 接线 + 默认 Noop 零破坏(§2.3)→ Task 6 + 各 service 默认参数。✅
- 同步埋点地图(§3.1):`sync.push`(Task 8)、`sync.push_batch`(Task 8)、`sync.partial_ack`/`sync.push.strike`/`sync.deadletter`/`sync.ack_removal`/`sync.deadletter.cleared`(Task 7)、`sync.pull`/`sync.migrate`/`sync.conflict`(Task 8-9)。`sync.realtime` 因 non-throwing 流无 catch 点,Phase 1 不实现(spec §3.1 列出但本计划显式跳过 —— realtime 失败要可观测需先改 `RemotePantryRepository` 的流为可报错,属后续)。✅(含一处显式缩减说明)
- 隐私口径(§4):tags 全为低基数非内容;`fieldCount` 替字段名;`durationMs` 只进 breadcrumb。✅
- 错误处理不变量(§5):门面方法不抛(measure 仅 rethrow);默认 Noop。✅
- 测试策略(§6):SpyDiagnostics(Task 2)、measure 单测(Task 2)、同步接缝 spy 测试(Task 7)、Noop 默认保现有测试不变(Task 10)。✅
- 分阶段(§7):Phase 1 全细化,Phase 2-4 路线图。✅

**2. 占位扫描:** 无 TBD/TODO;每个代码步骤含完整代码;Phase 2-4 明确标注为"开始时展开",非伪 bite-sized。✅

**3. 类型一致性:** `Diagnostics`/`breadcrumb(_:_:)`/`failure(_:error:_:)`/`measure(_:_:_:)`/`diagnosticErrorClass(_:)`/`NoopDiagnostics`/`SpyDiagnostics`/`DiagnosticsFactory.make(sentryConfig:)` 全计划一致;三个 service 的 `diagnostics:` 参数标签与 `AppDependencies` 调用点一致;`SyncCoordinator(... diagnostics:)` 在测试与 DI 用法一致。✅
