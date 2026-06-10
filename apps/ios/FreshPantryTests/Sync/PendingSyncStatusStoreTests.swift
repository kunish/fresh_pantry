import Foundation
import Testing
@testable import FreshPantry

/// Tests for `PendingSyncStatusStore` — the @MainActor store backing the per-row
/// 「待同步」 badge. Exercises the pure refresh / membership logic against an
/// injected in-memory `PendingSyncReading` fake (no SwiftData, no Supabase).
@MainActor
struct PendingSyncStatusStoreTests {
    /// In-memory outbox-read fake (actor — matches `SyncCoordinatorTests`'s
    /// `FakeOutbox` and keeps mutable state concurrency-safe without
    /// `@unchecked`). `ids` is mutable so a test can simulate the set changing
    /// between refreshes (an enqueue, then an ack); `shouldThrow` drives the
    /// best-effort failure path.
    private actor FakeOutbox: PendingSyncReading {
        private var ids: Set<String>
        private var shouldThrow = false

        init(ids: Set<String> = []) { self.ids = ids }

        func setIDs(_ next: Set<String>) { ids = next }
        func setShouldThrow(_ value: Bool) { shouldThrow = value }

        func pendingEntityIDs() async throws -> Set<String> {
            if shouldThrow { throw CancellationError() }
            return ids
        }
    }

    // MARK: Initial state

    @Test func startsEmptyBeforeFirstRefresh() {
        let store = PendingSyncStatusStore(outbox: FakeOutbox(ids: ["ing_1"]))
        // No refresh yet → nothing pending (badges off until the first read).
        #expect(store.pendingEntityIDs.isEmpty)
        #expect(store.isPending("ing_1") == false)
    }

    // MARK: Refresh pulls the set

    @Test func refreshPullsThePendingSet() async {
        let outbox = FakeOutbox(ids: ["ing_1", "si_9"])
        let store = PendingSyncStatusStore(outbox: outbox)

        await store.refresh()

        #expect(store.pendingEntityIDs == ["ing_1", "si_9"])
        #expect(store.isPending("ing_1"))
        #expect(store.isPending("si_9"))
        #expect(store.isPending("ing_2") == false)
    }

    // MARK: Membership of a blank id

    @Test func blankIDIsNeverPending() async {
        let store = PendingSyncStatusStore(outbox: FakeOutbox(ids: ["ing_1"]))
        await store.refresh()
        // A freshly-created local row with no id can't be in the outbox.
        #expect(store.isPending("") == false)
    }

    // MARK: Refresh reflects a later change (enqueue → ack)

    @Test func refreshReflectsAnUpdatedSet() async {
        let outbox = FakeOutbox(ids: ["ing_1"])
        let store = PendingSyncStatusStore(outbox: outbox)
        await store.refresh()
        #expect(store.isPending("ing_1"))

        // Simulate the row being acknowledged + a new row enqueued.
        await outbox.setIDs(["ing_2"])
        await store.refresh()

        #expect(store.isPending("ing_1") == false)
        #expect(store.isPending("ing_2"))
    }

    // MARK: Best-effort failure keeps the last good set

    @Test func failedRefreshKeepsLastGoodSet() async {
        let outbox = FakeOutbox(ids: ["ing_1"])
        let store = PendingSyncStatusStore(outbox: outbox)
        await store.refresh()
        #expect(store.isPending("ing_1"))

        // A failing read must NOT flash every badge off — keep the prior set.
        await outbox.setShouldThrow(true)
        await store.refresh()
        #expect(store.isPending("ing_1"))
        #expect(store.pendingEntityIDs == ["ing_1"])
    }
}
