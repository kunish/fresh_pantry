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
    ///
    /// - Note: `outcome`/`durationMs`/`errorClass` 由 `measure` 自动注入,
    ///   `diagnostic` 由 Sentry sink 作为保留 key 写入;调用方不应在 `tags` 里
    ///   传这些 key,否则可能被覆盖或产生歧义。
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
