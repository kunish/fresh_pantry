import Foundation
import SwiftData

/// Shopping-list CRUD with category normalization + case-insensitive name dedup
/// applied on BOTH load and remote-merge (the original divergence bug was
/// deduping in only one path). Mirrors `lib/storage/shopping_repo.dart`.
@ModelActor
actor ShoppingRepository {
    /// SELECT scope; per-row decode + category-normalize (skip malformed); then
    /// dedupe by case-insensitive name.
    func loadAllFor(_ householdID: String) throws -> [ShoppingItem] {
        // Sorted by id so the case-insensitive name dedup ("keep first") is
        // deterministic — SwiftData fetch order is otherwise unspecified.
        let descriptor = FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { $0.householdID == householdID },
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        let items = rows.compactMap { row -> ShoppingItem? in
            guard let item = try? row.item() else { return nil }
            return ShoppingItemNormalizer.normalizeCategory(item)
        }
        return ShoppingItemNormalizer.deduplicate(items)
    }

    /// Remote-merge entry point: same dedup must run here so the reloaded and
    /// in-memory lists cannot diverge.
    func mergeFromRemote(_ items: [ShoppingItem]) -> [ShoppingItem] {
        ShoppingItemNormalizer.deduplicate(items.map(ShoppingItemNormalizer.normalizeCategory))
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: ShoppingItemRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    /// Replace the whole household scope. `id` is the natural key (unique).
    func saveItems(_ householdID: String, _ items: [ShoppingItem]) throws {
        try modelContext.delete(
            model: ShoppingItemRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for item in items {
            let id = item.id.trimmed
            if id.isEmpty || seenIds.contains(id) { continue }
            seenIds.insert(id)
            modelContext.insert(ShoppingItemRecord(householdID: householdID, item: item))
        }
        try modelContext.save()
    }
}
