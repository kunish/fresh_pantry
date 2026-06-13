# 诊断埋点(Diagnostics Telemetry)设计

- 日期:2026-06-13
- 状态:已批准设计,待写实现计划
- 目标平台:`apps/ios`(SwiftUI iOS app)

## 1. 目标与背景

给 app 的关键流程加**诊断/可观测性**埋点,工程视角:看关键操作有没有出错、失败率与耗时,从 TestFlight 用户那里把线上问题排查出来。

当前现状(侦察结论):

- 仅集成 **Sentry**(`SentryBootstrap`),且只用于**错误/崩溃监控 + session replay**,未用任何事件级 API(`captureEvent`/`addBreadcrumb`/span 均未调用)。
- 6 处使用系统 `os.Logger` 做**本地诊断日志**,无远程上报能力。
- 后端有 `sync_events` 表,但那是**同步审计**,不是用户行为/诊断分析,iOS 端也未向其写入。
- 没有任何第三方分析 SDK(无 Mixpanel/Firebase/Amplitude/PostHog)。

### 已定决策(来自 brainstorm 问答)

| 维度 | 决策 |
|---|---|
| 埋点目的 | **诊断 / 可观测性**(非产品分析、非第三方 SDK) |
| 覆盖范围 | 四个关键流程全覆盖:同步、登录/认证、扫码/营养/入库、做菜扣减+备份 |
| 事件落点(sink) | **复用已有 Sentry**(零新依赖、低 churn) |
| 实现策略 | spec 覆盖全 4 流程,**实现分阶段**(先门面+同步跑通,再增量加另三条) |
| DEBUG 行为 | **OSLog 镜像**(本地可见,永不进 Sentry) |
| 代码落点 | `Services/Diagnostics/` |

### 非目标(YAGNI)

- 不引入第三方产品分析 SDK。
- 不建 Supabase `diagnostic_events` 表 / 离线上报队列(诊断只走 Sentry;若将来要 SQL 查成功率分位,作为独立升级项另行评估)。
- 不做产品漏斗/留存/DAU 这类业务分析(那是另一个目的,需要单独立项)。
- 不改动 Sentry 现有的崩溃监控 / replay 配置。

## 2. 架构

### 2.1 门面(facade)—— 全 app 只对这一层编程

新增 `Services/Diagnostics/Diagnostics.swift`,一个 `Sendable` 协议,3 个原语:

```swift
protocol Diagnostics: Sendable {
    /// 操作轨迹,只留痕不上报(Sentry breadcrumb)。
    func breadcrumb(_ name: String, _ tags: [String: String])

    /// 一次失败 → Sentry captureEvent(level=.error,按 name+errorClass 聚合
    /// fingerprint,带结构化 tags)。error 可空(逻辑失败无 throw 时)。
    func failure(_ name: String, error: Error?, _ tags: [String: String])

    /// 包裹一次异步操作:开始留痕 + Sentry span 计时 + 抛错自动 failure +
    /// 透传(rethrows)底层结果与错误。耗时(durationMs)随 span/事件记录。
    func measure<T>(_ name: String, _ tags: [String: String],
                    _ work: () async throws -> T) async rethrows -> T
}
```

设计意图:

- 大多数调用点只用 `measure {}`,一次拿到 开始 / 成功 / 失败 / 耗时。
- 像 `SyncCoordinator.strike` 这种"逻辑失败但没 throw"的点,直接调 `failure(...)`。
- **门面层永不 throw、永不影响 app 行为**:`measure` 只透传(rethrows)底层错误;`breadcrumb`/`failure` 内部 catch 一切。诊断的 bug 绝不能搞挂同步。

便利封装(可选,实现期定):为常见的"成功/失败两态"提供 `measure` 的非 throw 重载或 `outcome` tag 约定,避免调用点样板。

### 2.2 实现与开关(严格对齐现有 `SentryBootstrap` 的 DEBUG 门控)

三个实现:

- `SentryDiagnostics`(Release/Profile + 有 sentry 配置):breadcrumb → `SentrySDK.addBreadcrumb`;failure → `SentrySDK.capture(event:)`(设 `level`、`message=name`、`tags`、`fingerprint=[name, errorClass]`);measure → `SentrySDK.startTransaction` / 子 span,`finish(status:)` 带成功/失败状态。
- `OSLogDiagnostics`(DEBUG):打到 `os.Logger`(subsystem `com.kunish.freshPantry`,category `diagnostics`),本地可见,**永不进 Sentry** —— 与 `SentryBootstrap` 的 `#if !DEBUG` 一致(DEBUG 下 Sentry 整体禁用)。
- `NoopDiagnostics`(local-only 空 `Secrets` / 测试默认):什么都不做。

工厂:

```swift
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

门控逻辑刻意镜像 `SentryBootstrap.start`:DEBUG 不碰 Sentry;Release 无配置(OSS checkout / 空 Secrets)退化为 Noop;Release 有配置才真正上报。

`SentryDiagnostics` 假定 `SentrySDK` 已由 `SentryBootstrap.start` 启动;若未启动则其调用是无害 no-op(SDK 自身保证)。两者读同一份 `config.sentry`,不重复初始化 SDK。

### 2.3 DI 接线

`AppDependencies` 增加 `let diagnostics: Diagnostics`,在 `init` 里用工厂建一次(读 `config?.sentry`),注入到需要的 service:

- `SyncCoordinator`、`SupabaseSyncGateway`、`HouseholdContentSyncCoordinator`
- `AuthService`
- `OpenFoodFactsDetailsClient`(`FoodDetailsClient` 实现)
- `DeductionController`
- `BackupService`

**关键:每个 service 的构造器给 `diagnostics: Diagnostics = NoopDiagnostics()` 默认参数**,使得现有全部调用点与 669 个测试零改动、零破坏 —— 只有 `AppDependencies` 这一处显式传入真实实现。

`Diagnostics: Sendable` 保证可跨 actor 边界(`SyncCoordinator` 是 actor、`AuthService` 是 `@MainActor @Observable`);`SentryDiagnostics` 包裹的是线程安全的 `SentrySDK` 全局静态接口。

## 3. 埋点地图(四个流程)

事件命名规范:`<domain>.<op>[.<detail>]`,稳定 dotted id,便于在 Sentry 里聚合分组。

### 3.1 同步(最脆弱 —— 第一阶段优先)

| 接缝(文件) | 事件 | 说明 |
|---|---|---|
| `Sync/SupabaseSyncGateway.swift` `pushOperations` | `sync.push` | measure 网络推送延迟 + 失败;**当前这里吞掉了错误类型**,捕获后终于能看清同步为什么失败(历史「对方看不到」「静默吞错」根因点) |
| `Sync/SyncCoordinator.swift` `pushOnce` | `sync.partial_ack` | 静默部分 ack(`acknowledged.count < active.count`)失败 |
| | `sync.push.strike` | `strike()` 命中(tags:`entityType`、`attempt`) |
| | `sync.deadletter` | 实体进入隔离(tags:`entityType`)/ `clearDeadLetters` 用户丢弃未同步写入 |
| | `sync.ack_removal` | `outbox.removeAcknowledged` 失败(当前仅 OSLog,补一条 failure) |
| `Sync/HouseholdContentSyncCoordinator.swift` | `sync.pull`、`sync.realtime` | 拉取/合并失败、realtime 订阅断开 |

### 3.2 登录 / 认证

| 接缝(文件) | 事件 | 说明 |
|---|---|---|
| `Features/Auth/AuthService.swift` `run(_:)`(中央 catch,加 `name` 参数) | `auth.send_code`、`auth.verify` | failure 带 `errorClass`(`AuthFailure` 子类 / generic);verify 失败是登录漏斗最顶端 |
| `sendCode`/`verify`/`restore`/`signOut` 成功转移 | `auth.code_sent`、`auth.signed_in`、`auth.restore`、`auth.signout` | breadcrumb 留痕 |

### 3.3 扫码 / 营养 / 入库

| 接缝(文件) | 事件 | 说明 |
|---|---|---|
| `Services/FoodDetailsClient.swift`(`OpenFoodFactsDetailsClient`)查询 | `scan.off_lookup` | measure OFF 查询成功率 + 延迟(依赖外部网络) |
| OFF 营养解析 | `scan.nutrition_parse` | 解析失败 |
| `Features/Inventory/AddIngredientView.swift` 条码 fast-path | `scan.resolve`(tag `source=local/off/manual`) | 条码解析来源漏斗(本地命中 > OFF > 手填) |
| 加入库存 | `scan.intake` | breadcrumb |

### 3.4 做菜扣减 + 备份

| 接缝(文件) | 事件 | 说明 |
|---|---|---|
| `Features/Recipes/DeductionController.swift` 应用扣减 | `cook.deduct` | 扣减成功/失败 + 耗时 |
| 食材去向自动写入(food log) | `cook.foodlog` | 自动 consumed 记录失败 |
| `Services/BackupService.swift` | `backup.export`、`backup.import`、`backup.restore` | 数据正确性关键,失败必捕获 |

## 4. 隐私口径(硬规则)

- tags 只放**低基数、非内容**维度:`entityType`、`errorClass`、`source`、`attempt`、`outcome`、`durationMs`。
- **绝不**放:食材名、邮箱、原始条码、明文 household id / user id(需要关联就 hash 后再放)。
- 登录流程里邮箱是 PII → 只打布尔 `had_email`,不打邮箱本身。
- `errorClass` 是错误**类型名 / 映射后的类别**,不是原始 error message(message 可能含用户数据)。
- 复用 Sentry 已有的 replay 全脱敏(`maskAllText/maskAllImages`)。

## 5. 错误处理不变量

- 诊断层任何方法都不得抛错给调用方(`measure` 仅 rethrows 底层 work 的错误,自身埋点逻辑全 catch)。
- 诊断失败 = 静默吞掉(最多 DEBUG 下 OSLog 一行),绝不冒泡、绝不影响业务路径。
- 注入默认 `NoopDiagnostics` 保证未接线的代码路径行为完全不变。

## 6. 测试策略

- `SpyDiagnostics`(测试替身):记录所有 `breadcrumb/failure/measure` 调用 → 断言各接缝在**失败路径**上发了正确的事件名与 tags。注入进 `SyncCoordinator`、`AuthService` 等已有测试。
- 门面自身单测:`measure` 在 成功 / 抛错 两路各发对应事件,`durationMs` 非空,抛错时 rethrows 原错误且额外发一条 `failure`。
- `NoopDiagnostics` 为默认 → 现有 669 测试行为不变、保持全绿。
- 不为 `SentryDiagnostics` 写网络断言(不打真实 Sentry);只验证它把调用正确翻译成 SDK 调用(可用轻量协议封装 `SentrySDK` 入口以便注入 spy,或仅做编译期/烟雾验证 —— 实现期定)。

## 7. 分阶段实现

每阶段独立可发、独立测试,不互相阻塞。

1. **Phase 1 — 门面 + 同步**:`Diagnostics` 协议 + 三实现 + 工厂 + DI 接线;埋同步流程(§3.1);门面单测 + 同步接缝 spy 测试。跑通一版端到端(Release 构建能在 Sentry 看到 `sync.*` 事件)。
2. **Phase 2 — 登录/认证**(§3.2)。
3. **Phase 3 — 扫码/营养/入库**(§3.3)。
4. **Phase 4 — 做菜扣减 + 备份**(§3.4)。

## 8. 待实现期确认的细节

- sentry-cocoa 9.17 的精确 API(`Breadcrumb`/`Event`/`startTransaction`/`finish(status:)` 签名)—— 实现时用 Context7 查当前文档核对。
- `measure` 是否提供非 throw 重载 / `outcome` tag 约定,减少调用点样板。
- `SentryDiagnostics` 的可测性封装方式(是否抽 `SentryClient` 协议薄封装)。
