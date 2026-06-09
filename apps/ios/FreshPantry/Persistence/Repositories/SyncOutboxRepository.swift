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

    /// Replace the whole outbox.
    func replaceAll(_ ops: [SyncOperation]) throws {
        try modelContext.delete(model: SyncOutboxRecord.self)
        for op in ops {
            modelContext.insert(SyncOutboxRecord(operation: op))
        }
        try modelContext.save()
    }
}
