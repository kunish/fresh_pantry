import Foundation
import SwiftData

/// Drift-backed sync outbox queue. Mirrors `lib/sync/sync_outbox_repo.dart`
/// (minus the Riverpod in-memory cache + watch stream).
@ModelActor
actor SyncOutboxRepository {
    /// All pending operations, ordered by createdAt (oldest first).
    func loadPending() throws -> [SyncOperation] {
        let descriptor = FetchDescriptor<SyncOutboxRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).compactMap { try? $0.syncOperation() }
    }

    func pendingCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<SyncOutboxRecord>())
    }

    /// The distinct `entityID`s that currently have at least one queued (not yet
    /// acknowledged) outbox operation. Powers the per-row 「待同步」 badge: the UI
    /// pulls this ONCE per refresh and tests membership locally, instead of a
    /// per-row query.
    ///
    /// Returns a `Sendable Set<String>` (value, no `@Model` crosses the actor
    /// boundary). Fetches only the `entityID` projection column via the existing
    /// `SyncOutboxRecord` — no payload decode, so it stays cheap even with a deep
    /// offline backlog. Blank ids are dropped (they can't match a real row).
    func pendingEntityIDs() throws -> Set<String> {
        var descriptor = FetchDescriptor<SyncOutboxRecord>()
        descriptor.propertiesToFetch = [\.entityID]
        let records = try modelContext.fetch(descriptor)
        return Set(records.map(\.entityID).filter { !$0.isEmpty })
    }

    /// Insert-or-update by id.
    func enqueue(_ op: SyncOperation) throws {
        let id = op.id
        let existing = try modelContext.fetch(
            FetchDescriptor<SyncOutboxRecord>(predicate: #Predicate { $0.id == id })
        )
        if let row = existing.first {
            row.apply(op)
        } else {
            modelContext.insert(SyncOutboxRecord(operation: op))
        }
        try modelContext.save()
    }

    /// DELETE WHERE id IN ids (no-op when empty).
    func removeAcknowledged(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try modelContext.delete(
            model: SyncOutboxRecord.self,
            where: #Predicate { ids.contains($0.id) }
        )
        try modelContext.save()
    }
}
