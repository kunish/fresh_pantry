import Foundation

/// Shared optimistic-concurrency / soft-delete triplet embedded (flattened) by
/// every synced entity. Mirrors Flutter `SyncMetadata`.
///
/// - `remoteVersion`: last server-acked version (0 = never synced / local-only).
/// - `clientUpdatedAt`: local mutation timestamp for last-writer-wins.
/// - `deletedAt`: non-nil = soft-deleted (tombstone).
struct SyncMetadata: Equatable, Sendable {
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    init(remoteVersion: Int = 0, clientUpdatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }
}
