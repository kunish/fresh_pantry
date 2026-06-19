import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Tests for the **Sync Finish** seam — the one finishing sequence (coalesced
/// push → `pendingSyncRevision` bump, plus an optional cross-instance refresh
/// pulse) that every local write runs after touching the outbox. Both the
/// enqueue path AND the direct-outbox drainer path (the widget toggle, which
/// records its op out of band via `ShoppingToggleService`) must reach the SAME
/// finish, so a finishing step can't be dropped — the exact defect class behind
/// `c0defc8` (missing refresh pulse → stale list) and `dabcbd4` (missing
/// push+bump → stuck 「同步中,1 条待同步」).
///
/// A `CoordinatorPushing` spy makes *"did this write actually KICK a push?"*
/// assertable for the first time. The absence of that seam — `SyncCoordinator`
/// was a bare concrete actor — is the structural reason both bugs shipped past
/// the suite (every test could only observe the `pendingSyncRevision` proxy,
/// which can bump independently of an actual push).
@MainActor
struct SyncFinishTests {
    /// Counting push surface. `waitForPush()` lets a test deterministically join
    /// the enqueue path's fire-and-forget trailing push without polling.
    private actor PushSpy: CoordinatorPushing {
        private(set) var count = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func pushPending() async {
            count += 1
            let resume = waiters
            waiters.removeAll()
            for cont in resume { cont.resume() }
        }

        /// Suspends until at least one push has happened (returns immediately if
        /// one already has). Never call when no push is expected — it would hang.
        func waitForPush() async {
            if count > 0 { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private struct Fixture {
        let outbox: SyncOutboxRepository
        let session: SyncSession
        let spy: PushSpy
        let writer: SyncWriter
    }

    private func makeFixture(household: String) throws -> Fixture {
        let container = try ModelContainerFactory.makeInMemory()
        let outbox = SyncOutboxRepository(modelContainer: container)
        let defaults = UserDefaults(suiteName: "test.syncfinish.\(UUID().uuidString)")!
        let session = SyncSession(selectedHouseholdId: household, defaults: defaults)
        let spy = PushSpy()
        let writer = SyncWriter(outbox: outbox, coordinator: spy, session: session)
        return Fixture(outbox: outbox, session: session, spy: spy, writer: writer)
    }

    private func samplePatch() -> [String: JSONValue] {
        ["name": .string("番茄"), "quantity": .double(2.5)]
    }

    // MARK: - Enqueue path kicks the shared finish

    @Test func enqueueWithRecordedOpKicksPush() async throws {
        let f = try makeFixture(household: "home")

        await f.writer.enqueue(
            entityType: .shoppingItem, entityId: "si_1",
            operation: .create, patch: samplePatch(), baseVersion: nil
        )
        await f.spy.waitForPush()

        // A recorded op funnels into the finish → exactly one coalesced push.
        #expect(await f.spy.count == 1)
    }

    @Test func enqueueWithBlankHouseholdKicksNoPush() async throws {
        let f = try makeFixture(household: "")

        await f.writer.enqueue(
            entityType: .shoppingItem, entityId: "si_1",
            operation: .create, patch: samplePatch(), baseVersion: nil
        )

        // Whole-batch no-op (local-only): nothing recorded → the finish never runs.
        #expect(await f.spy.count == 0)
    }

    @Test func enqueueBatchWithEveryEntityIdBlankKicksNoPush() async throws {
        let f = try makeFixture(household: "home")
        let ops = (0..<3).map { _ in
            SyncWriter.PendingOp(
                entityType: .inventoryItem, entityId: "   ",
                operation: .create, patch: ["x": .int(1)], baseVersion: nil
            )
        }

        await f.writer.enqueueBatch(ops)

        // Every op skipped (blank entityId) → recordedAny stays false → the finish
        // is gated off, so a fully-unrecorded batch never spuriously clears the
        // 待同步 badge for a write that never persisted (the recordedAny gate).
        #expect(await f.spy.count == 0)
    }

    // MARK: - Direct-outbox finish (the widget drainer bypass)

    @Test func directOutboxFinishInHouseholdRunsFullFinish() async throws {
        let f = try makeFixture(household: "home")
        let before = f.session.pendingSyncRevision
        var refreshed = 0

        await f.writer.finishDirectOutboxWrite(didWrite: true) { refreshed += 1 }

        // The bypass path (op enqueued out of band) reaches the SAME finish:
        // refresh pulse fired, push kicked, badge revision bumped — the exact tail
        // dabcbd4 (push+bump) and c0defc8 (pulse) dropped. This is the test that
        // would have caught both.
        #expect(refreshed == 1)
        #expect(await f.spy.count == 1)
        #expect(f.session.pendingSyncRevision == before + 1)
    }

    @Test func directOutboxFinishWithoutWriteDoesNothing() async throws {
        let f = try makeFixture(household: "home")
        let before = f.session.pendingSyncRevision
        var refreshed = 0

        await f.writer.finishDirectOutboxWrite(didWrite: false) { refreshed += 1 }

        // No real flip → no reload, no push, no badge churn.
        #expect(refreshed == 0)
        #expect(await f.spy.count == 0)
        #expect(f.session.pendingSyncRevision == before)
    }

    @Test func directOutboxFinishLocalOnlyRefreshesButDoesNotPush() async throws {
        let f = try makeFixture(household: "")
        let before = f.session.pendingSyncRevision
        var refreshed = 0

        await f.writer.finishDirectOutboxWrite(didWrite: true) { refreshed += 1 }

        // Local-only flip: the foreground list still reloads, but nothing was
        // enqueued so there is nothing to push and no badge to converge.
        #expect(refreshed == 1)
        #expect(await f.spy.count == 0)
        #expect(f.session.pendingSyncRevision == before)
    }
}
