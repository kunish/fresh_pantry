import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the 库存不足 (常买补货) feature store: the count≥3 +
/// not-in-inventory filter, count-desc sort, selection defaults/toggle, and
/// category grouping. Seeded through a real in-memory `InventoryRepository` so the
/// add-history → `FrequentItem` derivation and the inventory presence check
/// compose exactly as in production.
@MainActor
struct LowStockStoreTests {
    private func makeRepo() throws -> InventoryRepository {
        let container = try ModelContainerFactory.makeInMemory()
        return InventoryRepository(modelContainer: container)
    }

    private func ingredient(_ name: String, category: String = FoodCategories.other) -> Ingredient {
        Ingredient(
            name: name, quantity: "1", unit: "个", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: category, storage: .fridge
        )
    }

    /// Bumps the add-history count for `name` by recording it `count` times.
    private func recordAdditions(
        _ repo: InventoryRepository,
        _ name: String,
        count: Int,
        category: String = FoodCategories.other
    ) async throws {
        for _ in 0..<count {
            try await repo.recordAddition(ingredient(name, category: category))
        }
    }

    private func makeStore(_ repo: InventoryRepository, household: String = "home") async -> LowStockStore {
        let store = LowStockStore(repository: repo, householdID: household)
        await store.load()
        return store
    }

    // MARK: Filter + sort

    @Test func keepsCountThreeAndAboveNotInInventorySortedDesc() async throws {
        let repo = try makeRepo()
        try await recordAdditions(repo, "牛奶", count: 5)
        try await recordAdditions(repo, "鸡蛋", count: 3)
        try await recordAdditions(repo, "酱油", count: 2) // below threshold → excluded

        let store = await makeStore(repo)
        // count desc: 牛奶(5) → 鸡蛋(3); 酱油(2) dropped.
        #expect(store.items.map(\.name) == ["牛奶", "鸡蛋"])
        #expect(store.items.map(\.count) == [5, 3])
    }

    @Test func excludesNamesCurrentlyInInventoryEvenWithHighCount() async throws {
        let repo = try makeRepo()
        try await recordAdditions(repo, "牛奶", count: 8)
        try await recordAdditions(repo, "鸡蛋", count: 4)
        // 牛奶 is back in stock → must not appear despite the highest count.
        try await repo.saveItems("home", [ingredient(" 牛奶 ")]) // trim/case-insensitive

        let store = await makeStore(repo)
        #expect(store.items.map(\.name) == ["鸡蛋"])
    }

    @Test func emptyWhenNoFrequentCandidates() async throws {
        let repo = try makeRepo()
        try await recordAdditions(repo, "酱油", count: 1)
        let store = await makeStore(repo)
        #expect(store.items.isEmpty)
        #expect(store.chosenItems.isEmpty)
        #expect(store.groupedByCategory.isEmpty)
    }

    // MARK: Selection

    @Test func selectionDefaultsToAllCandidates() async throws {
        let repo = try makeRepo()
        try await recordAdditions(repo, "牛奶", count: 5)
        try await recordAdditions(repo, "鸡蛋", count: 3)

        let store = await makeStore(repo)
        #expect(store.selectedNames == ["牛奶", "鸡蛋"])
        #expect(Set(store.chosenItems.map(\.name)) == ["牛奶", "鸡蛋"])
    }

    @Test func toggleFlipsSelectionMembership() async throws {
        let repo = try makeRepo()
        try await recordAdditions(repo, "牛奶", count: 5)
        try await recordAdditions(repo, "鸡蛋", count: 3)
        let store = await makeStore(repo)

        store.toggle("牛奶") // deselect
        #expect(store.selectedNames == ["鸡蛋"])
        #expect(store.chosenItems.map(\.name) == ["鸡蛋"])

        store.toggle("牛奶") // reselect
        #expect(store.selectedNames == ["牛奶", "鸡蛋"])
    }

    @Test func reloadPreservesPriorDeselection() async throws {
        let repo = try makeRepo()
        try await recordAdditions(repo, "牛奶", count: 5)
        try await recordAdditions(repo, "鸡蛋", count: 3)
        let store = await makeStore(repo)

        store.toggle("牛奶") // user de-selects 牛奶
        await store.load()    // a refresh must not re-default to all
        #expect(store.selectedNames == ["鸡蛋"])
    }

    // MARK: Grouping

    @Test func groupingPreservesCountDescWithinCategory() async throws {
        let repo = try makeRepo()
        // Two 肉类海鲜 candidates with different counts + one 乳品蛋类.
        try await recordAdditions(repo, "牛肉", count: 6, category: FoodCategories.meatAndSeafood)
        try await recordAdditions(repo, "鸡肉", count: 4, category: FoodCategories.meatAndSeafood)
        try await recordAdditions(repo, "牛奶", count: 5, category: FoodCategories.dairyAndEggs)

        let store = await makeStore(repo)
        let groups = store.groupedByCategory
        // Groups in canonical FoodCategories order: 乳品蛋类 before 肉类海鲜.
        #expect(groups.map(\.category) == [FoodCategories.dairyAndEggs, FoodCategories.meatAndSeafood])
        // Within 肉类海鲜, count desc: 牛肉(6) → 鸡肉(4).
        let meat = groups.first { $0.category == FoodCategories.meatAndSeafood }
        #expect(meat?.items.map(\.name) == ["牛肉", "鸡肉"])
    }
}
