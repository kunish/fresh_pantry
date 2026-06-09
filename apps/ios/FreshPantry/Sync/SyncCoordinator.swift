import Foundation

/// Remote push surface the coordinator depends on, so retry logic can be unit
/// tested without binding to the Supabase SDK. The SDK-backed gateway conforms
/// in a later slice. Mirrors the Dart `RemoteSyncGateway`.
protocol RemoteSyncGateway: Sendable {
    /// Pushes `ops` and returns the set of operation ids the server
    /// acknowledged (and therefore may be dropped from the outbox).
    func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String>
}

/// Outbox read/ack surface the coordinator depends on, so retry logic can be
/// unit tested without binding to SwiftData. The real `SyncOutboxRepository`
/// actor conforms in a later slice. Mirrors the Dart `OutboxReader`.
protocol OutboxReading: Sendable {
    /// Pending operations, oldest first.
    func loadPending() async throws -> [SyncOperation]

    /// Drops the acknowledged operations from the outbox.
    func removeAcknowledged(_ ids: Set<String>) async throws
}

/// Drives outbox push without overlapping runs, ported from
/// `lib/sync/sync_coordinator.dart`.
///
/// `pushPending` is invoked after every enqueue and during startup, so
/// concurrent callers must be coalesced: overlapping the snapshot → push →
/// remove cycle would double-push the same operations (a second run reads a
/// stale snapshot that still contains operations the first run is
/// acknowledging). Callers that arrive while a run is in flight join it, and
/// exactly one trailing run is scheduled afterwards so operations enqueued
/// mid-run (which the in-flight snapshot missed) are still pushed promptly.
///
/// Single-flight is enforced by actor isolation rather than a Dart `Future`
/// field: the `inFlight` task and `rerunRequested` flag are only ever touched
/// inside the actor.
actor SyncCoordinator {
    private let outbox: OutboxReading
    private let remote: RemoteSyncGateway
    private let retry: SyncRetryPolicy

    private var inFlight: Task<Void, Never>?
    private var rerunRequested = false

    init(
        outbox: OutboxReading,
        remote: RemoteSyncGateway,
        retry: SyncRetryPolicy = SyncRetryPolicy()
    ) {
        self.outbox = outbox
        self.remote = remote
        self.retry = retry
    }

    /// Pushes the queued outbox operations without overlapping runs. A caller
    /// arriving mid-run requests a trailing rerun and joins the in-flight task
    /// instead of starting a second concurrent run.
    func pushPending() async {
        if let inFlight {
            rerunRequested = true
            await inFlight.value
            return
        }
        await start().value
    }

    /// Starts a run and registers its completion handler. On completion it
    /// clears `inFlight` and, if a rerun was requested during the run, clears
    /// the flag and starts exactly one more run — the trailing rerun that
    /// catches ops enqueued mid-run. Returns the task so `pushPending` can join.
    private func start() -> Task<Void, Never> {
        let task = Task { [self] in
            await pushOnce()
            onRunComplete()
        }
        inFlight = task
        return task
    }

    /// Completion bookkeeping, run on the actor. Kept separate from `start` so
    /// the trailing-rerun decision is a single atomic, actor-isolated step.
    private func onRunComplete() {
        inFlight = nil
        guard rerunRequested else { return }
        rerunRequested = false
        _ = start()
    }

    /// Read-only view of the coalescing state, for deterministic testing of the
    /// single-flight + exactly-one-trailing-rerun guard. `(true, true)` means a
    /// run is in flight and a trailing rerun is already queued — the point at
    /// which any further `pushPending` caller must simply join.
    var coalescingState: (inFlight: Bool, rerunRequested: Bool) {
        (inFlight != nil, rerunRequested)
    }

    /// One snapshot → push → ack cycle with bounded retries. Leaves operations
    /// in the outbox (for the next trigger) on a permanent error or exhausted
    /// retries; never crashes. Mirrors the Dart `_pushPending`.
    private func pushOnce() async {
        guard let pending = try? await outbox.loadPending(), !pending.isEmpty else {
            return
        }

        for attempt in 1...retry.maxAttempts {
            do {
                let acknowledged = try await remote.pushOperations(pending)
                try await outbox.removeAcknowledged(acknowledged)
                return
            } catch {
                let lastAttempt = attempt == retry.maxAttempts
                if lastAttempt || !isTransientSyncError(error) {
                    // Permanent error or retries exhausted: leave ops in the
                    // outbox to be retried on the next trigger (reconnect /
                    // foreground / background).
                    return
                }
                try? await Task.sleep(for: retry.delayFor(attempt: attempt))
            }
        }
    }
}
