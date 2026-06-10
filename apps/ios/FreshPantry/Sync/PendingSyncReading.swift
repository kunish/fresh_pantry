import Foundation

/// Read-only outbox surface for the per-row 「待同步」 visibility feature, so the
/// `PendingSyncStatusStore` refresh logic can be unit-tested against a fake
/// without binding to SwiftData. Mirrors the `OutboxReading` seam used by the
/// coordinator. The real `SyncOutboxRepository` actor conforms below.
///
/// This is strictly READ-ONLY — it never touches the write/ack path, so adding
/// it can't change sync semantics (the feature only surfaces existing state).
protocol PendingSyncReading: Sendable {
    /// The distinct `entityID`s with at least one queued outbox operation.
    func pendingEntityIDs() async throws -> Set<String>
}

/// The persistent outbox actor's `pendingEntityIDs() throws -> Set<String>` is
/// synchronous-throwing, but a cross-actor call is implicitly `async`, so the
/// bare conformance satisfies the protocol's `async throws` requirement without
/// a bridging method (same pattern as `OutboxReading`).
extension SyncOutboxRepository: PendingSyncReading {}
