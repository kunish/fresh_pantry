import Foundation
import SwiftData

/// SwiftData-backed cache for OFF food details, keyed by
/// `FoodDetailsCacheRecord.cacheKey(for:)` (`barcode:<…>` / `name:<…>`).
/// Mirrors the read/write half of `lib/storage/food_details_repo.dart` (the
/// network fetch + fallback lives in `OpenFoodFactsService` / `FoodDetailsStore`).
///
/// The cache is VERSION-GATED (INVARIANT #9): a record whose `cacheVersion`
/// differs from `FoodDetails.cacheVersion` is treated as a MISS, so a
/// stale-schema payload (e.g. a pre-nutrition v4 row) is never deserialized as
/// the current shape — it gets re-fetched instead.
@ModelActor
actor FoodDetailsRepository {
    /// Return the cached details for an ingredient, or `nil` when absent OR the
    /// stored `cacheVersion` no longer matches the current schema.
    func cached(for ingredient: Ingredient) throws -> FoodDetails? {
        let key = FoodDetailsCacheRecord.cacheKey(for: ingredient)
        let descriptor = FetchDescriptor<FoodDetailsCacheRecord>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        guard let row = try modelContext.fetch(descriptor).first else { return nil }
        guard row.cacheVersion == FoodDetails.cacheVersion else { return nil }
        return try row.details()
    }

    /// Upsert the details for an ingredient by cache key (apply on an existing
    /// row, else insert). Stamps the current `cacheVersion`.
    func store(_ details: FoodDetails, for ingredient: Ingredient) throws {
        let key = FoodDetailsCacheRecord.cacheKey(for: ingredient)
        let descriptor = FetchDescriptor<FoodDetailsCacheRecord>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        if let row = try modelContext.fetch(descriptor).first {
            row.apply(details)
        } else {
            modelContext.insert(FoodDetailsCacheRecord(cacheKey: key, details: details))
        }
        try modelContext.save()
    }
}
