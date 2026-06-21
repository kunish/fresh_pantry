import Foundation

/// Conforms the persistent outbox actor to the coordinator's read/ack surface.
///
/// `SyncCoordinator` depends only on `OutboxReading` (async) so its retry logic
/// can be unit-tested against fakes; the production actor supplies the real
/// SwiftData-backed queue here.
///
/// The actor's existing `loadPending() throws -> [SyncOperation]` and
/// `removeAcknowledged(_:) throws` are synchronous-throwing, but every call
/// from off the actor is implicitly `async` (actor hop). A cross-actor call
/// therefore satisfies the protocol's `async throws` requirements directly, so
/// the bare conformance compiles without bridging methods — leaving the
/// existing `SyncOutboxRepository.swift` untouched as required.
extension SyncOutboxRepository: OutboxReading {}

/// The outbox WRITE surface `SyncWriter` depends on, so the enqueue-FAILURE path
/// (a SwiftData write that throws) is assertable with a fake that throws. That
/// failure is the one genuinely silent local/remote drift after a write: the row
/// changed locally but no op queued, so it never syncs until re-edited. The
/// production actor's synchronous-throwing `enqueue` satisfies the `async throws`
/// requirement across the actor hop, so the conformance is bare.
protocol OutboxEnqueuing: Sendable {
    func enqueue(_ operation: SyncOperation) async throws
}

extension SyncOutboxRepository: OutboxEnqueuing {}
