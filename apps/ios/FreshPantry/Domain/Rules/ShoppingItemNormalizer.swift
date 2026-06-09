import Foundation

/// Shared shopping-item normalization, identity, and de-duplication helpers
/// ported from `lib/storage/shopping_item_normalizer.dart`. Centralized so the
/// repo (load/save) and any provider (remote-merge) share one source of truth.
enum ShoppingItemNormalizer {
    /// Canonical category fallback.
    static func normalizeCategory(_ item: ShoppingItem) -> ShoppingItem {
        let category = FoodCategories.normalize(item.category) ?? FoodCategories.other
        if category == item.category { return item }
        return item.copyWith(category: category)
    }

    /// Full normalization: canonical category plus trimmed name/detail.
    static func normalize(_ item: ShoppingItem) -> ShoppingItem {
        let normalized = normalizeCategory(item)
        let trimmedName = normalized.name.trimmed
        let trimmedDetail = normalized.detail.trimmed
        if trimmedName == normalized.name && trimmedDetail == normalized.detail {
            return normalized
        }
        return normalized.copyWith(name: trimmedName, detail: trimmedDetail)
    }

    /// Case-insensitive name key for duplicate-name guards.
    static func nameKey(_ name: String) -> String { name.trimmed.lowercased() }

    /// Returns `item` with an id guaranteed unique within `existingIds`,
    /// minting a fresh id for blank ids and suffixing collisions.
    static func withUniqueId(_ item: ShoppingItem, existingIds: inout Set<String>) -> ShoppingItem {
        let trimmedId = item.id.trimmed
        let baseId = trimmedId.isEmpty ? ShoppingItem.newId() : trimmedId
        var candidateId = baseId
        var suffix = 2
        while existingIds.contains(candidateId) {
            candidateId = "\(baseId)_\(suffix)"
            suffix += 1
        }
        existingIds.insert(candidateId)
        return candidateId == item.id ? item : item.copyWith(id: candidateId)
    }

    /// De-duplicates by case-insensitive name (first wins), dropping blank-name
    /// rows; survivors get unique ids. Applied on load AND remote-merge.
    static func deduplicate(_ items: [ShoppingItem]) -> [ShoppingItem] {
        var seenNames = Set<String>()
        var seenIds = Set<String>()
        var deduplicated: [ShoppingItem] = []
        for item in items {
            let key = nameKey(item.name)
            if key.isEmpty || seenNames.contains(key) { continue }
            seenNames.insert(key)
            deduplicated.append(withUniqueId(item, existingIds: &seenIds))
        }
        return deduplicated
    }
}
