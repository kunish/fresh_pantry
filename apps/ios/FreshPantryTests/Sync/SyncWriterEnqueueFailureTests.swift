import Foundation
import Testing
@testable import FreshPantry

/// The enqueue-FAILURE contract — the one genuinely silent local/remote drift
/// after a local write. A PERSISTENT outbox write failure escalates to
/// `diagnostics.failure` (Sentry, not Console-only) and skips the finish (no
/// spurious 待同步 badge-clear for a write that never queued); a TRANSIENT failure
/// recovers via the bounded retry. Exercises `SyncWriter.record`.
@MainActor
struct SyncWriterEnqueueFailureTests {
    private struct EnqueueError: Error {}

    /// Always throws — a permanently-broken outbox write (disk full, migration).
    private actor FailingOutbox: OutboxEnqueuing {
        func enqueue(_ operation: SyncOperation) async throws { throw EnqueueError() }
    }

    /// Throws for the first `failFirst` attempts, then persists — a transient
    /// SwiftData write contention the retry should ride out.
    private actor FlakyOutbox: OutboxEnqueuing {
        private var failsRemaining: Int
        private var stored: [SyncOperation] = []
        init(failFirst: Int) { failsRemaining = failFirst }
        func enqueue(_ operation: SyncOperation) async throws {
            if failsRemaining > 0 {
                failsRemaining -= 1
                throw EnqueueError()
            }
            stored.append(operation)
        }
        func storedCount() -> Int { stored.count }
    }

    private actor PushSpy: CoordinatorPushing {
        private(set) var count = 0
        func pushPending() async { count += 1 }
    }

    private func makeSession(household: String = "home") -> SyncSession {
        SyncSession(
            selectedHouseholdId: household,
            defaults: UserDefaults(suiteName: "test.enqfail.\(UUID().uuidString)")!
        )
    }

    @Test func persistentFailureEscalatesNotesDropAndSkipsFinish() async {
        let spy = SpyDiagnostics()
        let push = PushSpy()
        let session = makeSession()
        let writer = SyncWriter(outbox: FailingOutbox(), coordinator: push, session: session, diagnostics: spy)

        await writer.enqueue(
            entityType: .inventoryItem, entityId: "ing_1",
            operation: .create, patch: ["name": .string("番茄")], baseVersion: nil
        )

        #expect(spy.failureNames.contains("sync.enqueue"))
        let fail = spy.failures.first { $0.name == "sync.enqueue" }!
        #expect(fail.tags["entityType"] == "inventoryItem")
        #expect(fail.tags["entityId"] == "ing_1")
        #expect(fail.errorClass != nil) // a real throw, not a logical failure
        // recordedAny stayed false → finish skipped → no push kicked for a lost write.
        #expect(await push.count == 0)
        // In-app signal: the drop is surfaced for the dismissible danger banner.
        #expect(session.droppedWriteCount == 1)
    }

    @Test func transientFailureRecoversWithoutEscalatingOrNotingDrop() async {
        let spy = SpyDiagnostics()
        let outbox = FlakyOutbox(failFirst: 1) // throws once, then succeeds
        let session = makeSession()
        let writer = SyncWriter(outbox: outbox, coordinator: PushSpy(), session: session, diagnostics: spy)

        await writer.enqueue(
            entityType: .shoppingItem, entityId: "si_1",
            operation: .create, patch: ["name": .string("牛奶")], baseVersion: nil
        )

        #expect(await outbox.storedCount() == 1)            // recovered: op persisted
        #expect(!spy.failureNames.contains("sync.enqueue")) // no escalation
        #expect(session.droppedWriteCount == 0)             // recovered → no drop notice
    }
}
