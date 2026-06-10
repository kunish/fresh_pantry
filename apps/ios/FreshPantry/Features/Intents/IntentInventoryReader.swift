import Foundation
import SwiftData

/// Read-only inventory loader for the query intent, scoped to the shared on-disk
/// container.
///
/// WHY A SEPARATE READER (not `InventoryRepository.loadAllFor`): the active
/// household id lives only in the in-memory `SyncSession` (resolved from the
/// network after sign-in) and is never persisted to disk, so a background intent
/// can't know which `householdID` scope to query. Reading EVERY non-soft-deleted
/// row instead is correct for the query's purpose: the local container only
/// retains the rows the sync engine has pulled for the device's current scope
/// (plus any local-only "" rows), so "all live rows" is the right offline answer
/// to "什么快过期了". Soft-deleted rows (`deletedAt != nil`) are excluded.
///
/// `@ModelActor` keeps SwiftData access off the main actor and only `Sendable`
/// `Ingredient` values cross the actor boundary (never a `@Model`), matching the
/// repository concurrency contract.
@ModelActor
actor IntentInventoryReader {
    /// All non-soft-deleted inventory items across every household scope present
    /// in the local store, freshness re-derived on read (same normalization the
    /// real repository applies). Malformed rows are skipped.
    func loadAllLive(now: Date = Date()) throws -> [Ingredient] {
        let descriptor = FetchDescriptor<InventoryItemRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.compactMap { row in
            guard let ingredient = try? row.ingredient() else { return nil }
            return IngredientNormalizer.normalizeInventoryIngredient(ingredient, now: now)
        }
    }
}
