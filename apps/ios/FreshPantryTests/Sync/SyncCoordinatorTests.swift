import Foundation
import Testing
@testable import FreshPantry

/// Retry-policy, coordinator, and upload-scope tests, driven through
/// deterministic fakes (NEVER the Supabase SDK or SwiftData). Mirrors the Dart
/// `sync_coordinator_test` / `sync_retry_policy_test` invariants.
struct SyncCoordinatorTests {
    // MARK: - Fakes

    /// A validation/auth failure — the permanent (non-retryable) error class.
    private struct ValidationError: Error {}

    /// An error whose description carries the `network` substring, standing in
    /// for the Dart string-match transient branch.
    private struct NetworkishError: Error, CustomStringConvertible {
        var description: String { "remote rejected: network unreachable" }
    }

    private func operation(
        id: String,
        householdId: String = "home",
        entityType: SyncEntityType = .inventoryItem,
        entityId: String = "ing_1"
    ) -> SyncOperation {
        SyncOperation(
            id: id, householdId: householdId, entityType: entityType,
            entityId: entityId, operation: .create, patch: [:],
            clientId: "client", createdAt: Date(timeIntervalSince1970: 1000)
        )
    }

    /// Deterministic in-memory outbox. Records the ack sets it was asked to drop.
    private actor FakeOutbox: OutboxReading {
        private var pending: [SyncOperation]
        private(set) var removedIDs: [Set<String>] = []

        init(pending: [SyncOperation]) { self.pending = pending }

        func loadPending() async throws -> [SyncOperation] { pending }

        func removeAcknowledged(_ ids: Set<String>) async throws {
            removedIDs.append(ids)
            pending.removeAll { ids.contains($0.id) }
        }

        func remainingIDs() -> Set<String> { Set(pending.map(\.id)) }
    }

    /// Gateway that records every push and replays a scripted result/throw per
    /// call. When `gated`, every push suspends until explicitly released, so a
    /// test can step through overlapping `pushPending()` invocations
    /// deterministically (wait for a push to arrive, release it, observe the
    /// next). Without gating, pushes complete immediately.
    private actor FakeGateway: RemoteSyncGateway {
        enum Outcome: Sendable {
            case acknowledge(Set<String>)
            case fail(any Error)
        }

        private var script: [Outcome]
        private let gated: Bool
        private(set) var pushedBatches: [[SyncOperation]] = []

        /// Continuations of gated pushes that have arrived and are suspended,
        /// in arrival order; `release()` resumes the oldest.
        private var waiting: [CheckedContinuation<Void, Never>] = []
        /// A test waiting for the next push to arrive (when none has yet).
        private var arrivalWaiter: CheckedContinuation<Void, Never>?

        init(script: [Outcome], gated: Bool = false) {
            self.script = script
            self.gated = gated
        }

        var pushCount: Int { pushedBatches.count }

        func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String> {
            pushedBatches.append(ops)
            if gated {
                await withCheckedContinuation { continuation in
                    waiting.append(continuation)
                    arrivalWaiter?.resume()
                    arrivalWaiter = nil
                }
            }
            let outcome = script.isEmpty ? Outcome.acknowledge([]) : script.removeFirst()
            switch outcome {
            case .acknowledge(let ids): return ids
            case .fail(let error): throw error
            }
        }

        /// Suspends until at least `count` gated pushes have arrived
        /// (cumulative, counted by `pushedBatches`, not the live suspended set).
        func awaitArrivals(_ count: Int) async {
            while pushedBatches.count < count {
                await withCheckedContinuation { arrivalWaiter = $0 }
            }
        }

        /// Resumes the oldest suspended gated push.
        func release() {
            guard !waiting.isEmpty else { return }
            waiting.removeFirst().resume()
        }
    }

    // MARK: - SyncRetryPolicy

    @Test func delayForFollowsExponentialSchedule() {
        let policy = SyncRetryPolicy()
        #expect(policy.delayFor(attempt: 1) == .milliseconds(500))
        #expect(policy.delayFor(attempt: 2) == .milliseconds(1000))
        #expect(policy.delayFor(attempt: 3) == .milliseconds(2000))
    }

    @Test func delayForClampsAtMaxDelay() {
        let policy = SyncRetryPolicy()
        // attempt 4 → 4000ms (under cap); attempt 5 → 8000ms (at cap);
        // attempt 6 would be 16000ms but clamps to the 8000ms ceiling.
        #expect(policy.delayFor(attempt: 4) == .milliseconds(4000))
        #expect(policy.delayFor(attempt: 5) == .milliseconds(8000))
        #expect(policy.delayFor(attempt: 6) == .milliseconds(8000))
    }

    @Test func isTransientForNetworkErrors() {
        #expect(isTransientSyncError(URLError(.timedOut)))
        #expect(isTransientSyncError(URLError(.notConnectedToInternet)))
        #expect(isTransientSyncError(NetworkishError())) // 'network' substring
    }

    @Test func isPermanentForValidationError() {
        #expect(!isTransientSyncError(ValidationError()))
    }

    // MARK: - SyncCoordinator

    @Test func emptyOutboxSkipsPush() async {
        let outbox = FakeOutbox(pending: [])
        let gateway = FakeGateway(script: [])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway)

        await coordinator.pushPending()

        #expect(await gateway.pushCount == 0)
        #expect(await outbox.removedIDs.isEmpty)
    }

    @Test func successfulPushRemovesExactlyAcknowledgedIDs() async {
        let outbox = FakeOutbox(pending: [
            operation(id: "op_1"), operation(id: "op_2"), operation(id: "op_3"),
        ])
        // Server acknowledges only op_1 and op_2.
        let gateway = FakeGateway(script: [.acknowledge(["op_1", "op_2"])])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway)

        await coordinator.pushPending()

        #expect(await gateway.pushCount == 1)
        #expect(await outbox.removedIDs == [["op_1", "op_2"]])
        #expect(await outbox.remainingIDs() == ["op_3"])
    }

    @Test func transientErrorRetriesThenGivesUpLeavingOps() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        // Every attempt fails transiently → all 4 attempts consumed, ops left.
        let gateway = FakeGateway(script: [
            .fail(URLError(.timedOut)),
            .fail(URLError(.timedOut)),
            .fail(URLError(.timedOut)),
            .fail(URLError(.timedOut)),
        ])
        // Tiny delays keep the test fast while still exercising the retry loop.
        let retry = SyncRetryPolicy(
            maxAttempts: 4, baseDelay: .milliseconds(1), maxDelay: .milliseconds(4))
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, retry: retry)

        await coordinator.pushPending()

        #expect(await gateway.pushCount == 4) // exhausts all attempts
        #expect(await outbox.removedIDs.isEmpty) // nothing acknowledged
        #expect(await outbox.remainingIDs() == ["op_1"]) // ops survive for next trigger
    }

    @Test func permanentErrorDoesNotRetry() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        let gateway = FakeGateway(script: [.fail(ValidationError())])
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway)

        await coordinator.pushPending()

        #expect(await gateway.pushCount == 1) // no retry on a permanent error
        #expect(await outbox.remainingIDs() == ["op_1"])
    }

    @Test func overlappingPushesCoalesceToOneRunPlusOneTrailingRerun() async {
        let outbox = FakeOutbox(pending: [operation(id: "op_1")])
        // Every push suspends until released, so we can step deterministically.
        let gateway = FakeGateway(
            script: [.acknowledge([]), .acknowledge([])], gated: true)
        let coordinator = SyncCoordinator(outbox: outbox, remote: gateway)

        // Kick the first run; it suspends inside the gated gateway.
        let firstRun = Task { await coordinator.pushPending() }
        await gateway.awaitArrivals(1)

        // While the first run is in flight, fire several more calls. Each must
        // join the in-flight task and collectively schedule exactly ONE rerun,
        // never a second concurrent run (which would re-read the stale snapshot
        // still holding op_1 and double-push it).
        let joiners = Task {
            async let j1: Void = coordinator.pushPending()
            async let j2: Void = coordinator.pushPending()
            async let j3: Void = coordinator.pushPending()
            _ = await (j1, j2, j3)
        }

        // Spin until the joiners have all entered: the in-flight guard holds
        // (the first run is gated, so `inFlight` is still set) AND a rerun is
        // queued. Reaching this state proves the joiners coalesced instead of
        // each spawning a fresh run. Only one push has happened so far.
        while await coordinator.coalescingState != (inFlight: true, rerunRequested: true) {
            await Task.yield()
        }
        #expect(await gateway.pushCount == 1)

        // Release the first push → the in-flight run completes and exactly one
        // trailing rerun starts and arrives at the gate.
        await gateway.release()
        await gateway.awaitArrivals(2)

        // Exactly two pushes: one in-flight run + one trailing rerun. The three
        // concurrent joiners spawned NO additional run.
        #expect(await gateway.pushCount == 2)

        // Drain the trailing rerun and confirm no further run materializes.
        await gateway.release()
        _ = await firstRun.value
        _ = await joiners.value
        // `firstRun`/`joiners` only joined the FIRST run; the trailing rerun's
        // completion bookkeeping (`onRunComplete` clearing `inFlight`) runs a few
        // async hops after its gated push returns, so spin until the coordinator
        // is fully quiescent rather than racing that final actor step.
        while await coordinator.coalescingState != (inFlight: false, rerunRequested: false) {
            await Task.yield()
        }
        // Exactly two pushes total — the three joiners spawned NO additional run.
        #expect(await gateway.pushCount == 2)
    }

    // MARK: - LocalUploadScope

    @Test func pendingOpForOtherHouseholdBlocksRowForThatHousehold() {
        let pending = [operation(id: "op_1", householdId: "A", entityId: "ing_1")]
        let scopeB = LocalUploadScope(householdID: "B", pendingOps: pending)
        let scopeA = LocalUploadScope(householdID: "A", pendingOps: pending)

        // Household B is blocked from a row claimed by A's pending op.
        #expect(!scopeB.allows(.inventoryItem, "ing_1"))
        // Household A — the op's own target — is permitted.
        #expect(scopeA.allows(.inventoryItem, "ing_1"))
    }

    @Test func rowWithNoPendingOpIsAllowed() {
        let scope = LocalUploadScope(householdID: "A", pendingOps: [])
        #expect(scope.allows(.inventoryItem, "ing_unclaimed"))
    }

    @Test func emptyEntityIDIsDenied() {
        let pending = [operation(id: "op_1", householdId: "A", entityId: "ing_1")]
        let scope = LocalUploadScope(householdID: "A", pendingOps: pending)
        #expect(!scope.allows(.inventoryItem, ""))
    }

    @Test func scopeKeysByEntityTypeNotJustID() {
        // Same entity id under a different entity type must not be blocked.
        let pending = [
            operation(id: "op_1", householdId: "A", entityType: .inventoryItem, entityId: "row")
        ]
        let scopeB = LocalUploadScope(householdID: "B", pendingOps: pending)
        #expect(!scopeB.allows(.inventoryItem, "row")) // claimed type → blocked
        #expect(scopeB.allows(.shoppingItem, "row")) // different type → free
    }
}
