import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// SwiftData round-trips through `BarcodeMemoryRepository` in an in-memory
/// container: upsert/lookup, idempotent overwrite (no duplicate rows), category
/// canonicalization, recency stamping, and the blank-barcode/blank-name guards.
@MainActor
struct BarcodeMemoryRepositoryTests {
    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    // MARK: upsert → lookup round-trip

    @Test func upsertThenLookupReturnsMapping() async throws {
        let repo = BarcodeMemoryRepository(modelContainer: try container())
        try await repo.upsert(barcode: "6901234567890", name: "三元鲜牛奶", category: FoodCategories.dairyAndEggs)

        let hit = try #require(try await repo.lookup("6901234567890"))
        #expect(hit.name == "三元鲜牛奶")
        #expect(hit.category == FoodCategories.dairyAndEggs)
        #expect(hit.barcode == "6901234567890")
    }

    @Test func lookupReturnsNilWhenAbsent() async throws {
        let repo = BarcodeMemoryRepository(modelContainer: try container())
        #expect(try await repo.lookup("0000000000000") == nil)
    }

    @Test func lookupTrimsBarcode() async throws {
        let repo = BarcodeMemoryRepository(modelContainer: try container())
        try await repo.upsert(barcode: "12345", name: "苹果", category: FoodCategories.freshProduce)
        // A whitespace-padded scan payload still resolves the same row.
        #expect(try await repo.lookup("  12345  ")?.name == "苹果")
    }

    @Test func lookupReturnsNilForBlankBarcode() async throws {
        let repo = BarcodeMemoryRepository(modelContainer: try container())
        #expect(try await repo.lookup("   ") == nil)
    }

    // MARK: Idempotent overwrite (no duplicate rows)

    @Test func upsertOverwritesSameBarcode() async throws {
        let modelContainer = try container()
        let repo = BarcodeMemoryRepository(modelContainer: modelContainer)
        try await repo.upsert(barcode: "999", name: "旧名字", category: FoodCategories.other)
        try await repo.upsert(barcode: "999", name: "新名字", category: FoodCategories.meatAndSeafood)

        let hit = try #require(try await repo.lookup("999"))
        #expect(hit.name == "新名字")
        #expect(hit.category == FoodCategories.meatAndSeafood)

        // Exactly one row for the key (update, not a second insert).
        let context = ModelContext(modelContainer)
        let rows = try context.fetch(
            FetchDescriptor<BarcodeMemoryRecord>(predicate: #Predicate { $0.barcode == "999" })
        )
        #expect(rows.count == 1)
    }

    @Test func upsertCanonicalizesCategory() async throws {
        let repo = BarcodeMemoryRepository(modelContainer: try container())
        // A legacy/alias label is normalized to a canonical category on write.
        try await repo.upsert(barcode: "555", name: "酸奶", category: "乳制品")
        #expect(try await repo.lookup("555")?.category == FoodCategories.dairyAndEggs)
    }

    @Test func upsertStampsRecency() async throws {
        let repo = BarcodeMemoryRepository(modelContainer: try container())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await repo.upsert(barcode: "777", name: "鸡蛋", category: FoodCategories.dairyAndEggs, now: now)
        #expect(try await repo.lookup("777")?.lastUsedAt == now)
    }

    // MARK: Guards — nothing useful to learn

    @Test func upsertIgnoresBlankBarcode() async throws {
        let modelContainer = try container()
        let repo = BarcodeMemoryRepository(modelContainer: modelContainer)
        try await repo.upsert(barcode: "  ", name: "无条码", category: FoodCategories.other)

        let context = ModelContext(modelContainer)
        let count = try context.fetchCount(FetchDescriptor<BarcodeMemoryRecord>())
        #expect(count == 0)
    }

    @Test func upsertIgnoresBlankName() async throws {
        let modelContainer = try container()
        let repo = BarcodeMemoryRepository(modelContainer: modelContainer)
        try await repo.upsert(barcode: "123", name: "   ", category: FoodCategories.other)

        let context = ModelContext(modelContainer)
        let count = try context.fetchCount(FetchDescriptor<BarcodeMemoryRecord>())
        #expect(count == 0)
    }
}
