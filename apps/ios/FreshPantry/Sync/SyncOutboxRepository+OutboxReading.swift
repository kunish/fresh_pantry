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
