import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// SwiftData round-trips through `FoodDetailsRepository` in an in-memory
/// container, covering the cache-version gate (INVARIANT #9) and cache-key
/// normalization.
@MainActor
struct FoodDetailsRepositoryTests {
    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    private func ingredient(name: String, barcode: String? = nil) -> Ingredient {
        Ingredient(
            id: "", name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, barcode: barcode
        )
    }

    private func details(displayName: String) -> FoodDetails {
        FoodDetails(
            displayName: displayName,
            description: "desc",
            imageUrl: "https://img/x.jpg",
            category: FoodCategories.dairyAndEggs,
            storage: .fridge,
            shelfLifeDays: 7,
            source: "Open Food Facts",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            nutrition: NutritionFacts(energyKcal: 100, protein: 5, carbs: 10, fat: 2)
        )
    }

    // MARK: Store → cached round-trip

    @Test func storeThenCachedReturnsDetails() async throws {
        let repo = FoodDetailsRepository(modelContainer: try container())
        let ing = ingredient(name: "牛奶")
        try await repo.store(details(displayName: "Milk"), for: ing)

        let cached = try await repo.cached(for: ing)
        let unwrapped = try #require(cached)
        #expect(unwrapped.displayName == "Milk")
        #expect(unwrapped.nutrition?.energyKcal == 100)
        #expect(unwrapped.category == FoodCategories.dairyAndEggs)
    }

    @Test func cachedReturnsNilWhenAbsent() async throws {
        let repo = FoodDetailsRepository(modelContainer: try container())
        #expect(try await repo.cached(for: ingredient(name: "不存在")) == nil)
    }

    @Test func storeUpsertsByCacheKey() async throws {
        let modelContainer = try container()
        let repo = FoodDetailsRepository(modelContainer: modelContainer)
        let ing = ingredient(name: "牛奶")
        try await repo.store(details(displayName: "Milk v1"), for: ing)
        try await repo.store(details(displayName: "Milk v2"), for: ing)

        let cached = try await repo.cached(for: ing)
        #expect(cached?.displayName == "Milk v2")

        // Upsert: exactly one row for the key (no duplicate insert).
        let context = ModelContext(modelContainer)
        let key = FoodDetailsCacheRecord.cacheKey(for: ing)
        let rows = try context.fetch(
            FetchDescriptor<FoodDetailsCacheRecord>(predicate: #Predicate { $0.cacheKey == key })
        )
        #expect(rows.count == 1)
    }

    // MARK: Cache-version gate (INVARIANT #9)

    @Test func staleCacheVersionIsTreatedAsMiss() async throws {
        let modelContainer = try container()
        let repo = FoodDetailsRepository(modelContainer: modelContainer)
        let ing = ingredient(name: "牛奶")

        // Insert a record carrying a pre-nutrition (v4) version directly, then
        // mutate the stored version so it no longer matches the current schema.
        let context = ModelContext(modelContainer)
        let key = FoodDetailsCacheRecord.cacheKey(for: ing)
        let record = FoodDetailsCacheRecord(cacheKey: key, details: details(displayName: "Stale"))
        record.cacheVersion = FoodDetails.cacheVersion - 1
        context.insert(record)
        try context.save()

        // A stale-schema row must NOT be deserialized as current → cache miss.
        #expect(try await repo.cached(for: ing) == nil)
    }

    @Test func currentCacheVersionIsAHit() async throws {
        let repo = FoodDetailsRepository(modelContainer: try container())
        let ing = ingredient(name: "牛奶")
        // store() stamps FoodDetails.cacheVersion → a hit.
        try await repo.store(details(displayName: "Fresh"), for: ing)
        #expect(try await repo.cached(for: ing)?.displayName == "Fresh")
    }

    // MARK: Cache-key normalization

    @Test func nameCacheKeyNormalizesWhitespaceAndCase() async throws {
        let repo = FoodDetailsRepository(modelContainer: try container())
        // Store under a messy name; read under a normalized variant resolves the
        // same key ("name:milk powder").
        try await repo.store(details(displayName: "Milk Powder"), for: ingredient(name: "  Milk   Powder  "))
        let cached = try await repo.cached(for: ingredient(name: "milk powder"))
        #expect(cached?.displayName == "Milk Powder")
    }

    @Test func barcodeKeyTakesPrecedenceOverName() async throws {
        let repo = FoodDetailsRepository(modelContainer: try container())
        // Same name, different barcode → distinct keys (barcode wins the key).
        try await repo.store(details(displayName: "By Barcode"), for: ingredient(name: "牛奶", barcode: "999"))
        // A name-only lookup (no barcode) must NOT hit the barcode-keyed row.
        #expect(try await repo.cached(for: ingredient(name: "牛奶")) == nil)
        #expect(try await repo.cached(for: ingredient(name: "牛奶", barcode: "999"))?.displayName == "By Barcode")
    }
}
