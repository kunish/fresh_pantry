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
