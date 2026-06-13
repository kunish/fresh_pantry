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

    private struct RemoveError: Error {}

    private actor FakeOutbox: OutboxReading {
        private var pending: [SyncOperation]
        private let removeThrows: Bool
        init(pending: [SyncOperation], removeThrows: Bool = false) {
            self.pending = pending
            self.removeThrows = removeThrows
        }
        func loadPending() async throws -> [SyncOperation] { pending }
        func removeAcknowledged(_ ids: Set<String>) async throws {
            if removeThrows { throw RemoveError() }
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
        #expect(dead.tags["entityType"] == "inventoryItem")
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
        #expect(crumb.tags["entityType"] == "inventoryItem")
    }

    @Test func ackRemovalFailureEmitsDiagnostic() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")], removeThrows: true)
        // 完整 ack → 不触发 partial_ack,只有 removeAcknowledged 抛错 → ack_removal failure。
        let gateway = FakeGateway(script: [.acknowledge(["op_1"])])
        let spy = SpyDiagnostics()
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, diagnostics: spy)

        await coordinator.pushPending()

        #expect(spy.failureNames.contains("sync.ack_removal"))
        let removal = spy.failures.first { $0.name == "sync.ack_removal" }!
        #expect(removal.errorClass != nil)
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
