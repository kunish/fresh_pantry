import Foundation

/// 所有被埋点接缝唯一编程对象的诊断门面。两个原语,具体 sink 只需实现
/// `breadcrumb` + `failure`。
///
/// 不变量:任何方法都不得因自身逻辑抛错、不得影响 app 行为;原语内部吞掉一切。
/// 诊断的 bug 绝不能搞挂功能。低基数纪律:只有低基数维度(entityType、source、
/// outcome、errorClass…)能进 tag;原始错误 message 绝不用作 tag。
protocol Diagnostics: Sendable {
    /// 操作轨迹 —— 留一条 Sentry breadcrumb,本身从不上报。`tags` 为低基数、
    /// 非 PII 维度(entityType、source、outcome…)。
    ///
    /// - Note: `diagnostic` 由 Sentry sink 作为保留 key 写入;调用方不应在 `tags`
    ///   里传该 key,否则可能被覆盖或产生歧义。
    func breadcrumb(_ name: String, _ tags: [String: String])

    /// 一次失败 → 一条 Sentry 事件(level=.error),按 `name` + 错误类名做
    /// fingerprint,使同一失败聚合成一个 issue。`error` 对从未 throw 的逻辑
    /// 失败(如同步 strike)为 nil。Sentry sink 会同时把失败镜像到 Logs+Metrics
    /// (见 `SentryDiagnostics.failure`),所以直接失败也能进可观测。
    func failure(_ name: String, error: Error?, _ tags: [String: String])
}

/// 错误的类型名 —— 一个可安全用作 Sentry tag 的低基数类别标签(原始错误
/// message 可能含用户数据,从不用作 tag)。
func diagnosticErrorClass(_ error: Error) -> String {
    String(describing: type(of: error))
}

/// 默认 sink:什么都不做。所有 service 构造器的默认值,保证未接线的代码路径
/// 与全部现有测试行为完全不变。
struct NoopDiagnostics: Diagnostics {
    func breadcrumb(_ name: String, _ tags: [String: String]) {}
    func failure(_ name: String, error: Error?, _ tags: [String: String]) {}
}
