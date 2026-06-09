import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Expiring feature store: non-fresh filtering, urgency
/// sort, tier sectioning, and the healthy-pantry empty case.
@MainActor
struct ExpiringStoreTests {
    private func makeStore(_ items: [Ingredient], household: String = "home") async throws -> ExpiringStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let store = ExpiringStore(repository: repo, householdID: household)
        await store.load()
        return store
    }

    private func item(id: String, name: String, state: FreshnessState) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: state, category: FoodCategories.other, storage: .fridge
        )
    }

    @Test func sortedItemsExcludesFreshAndOrdersBySeverity() async throws {
        let store = try await makeStore([
            item(id: "fresh", name: "苹果", state: .fresh),
            item(id: "soon", name: "酸奶", state: .expiringSoon),
            item(id: "expired", name: "菠菜", state: .expired),
            item(id: "urgent", name: "鸡肉", state: .urgent),
        ])
        // fresh dropped; expired → urgent → soon
        #expect(store.sortedItems.map(\.id) == ["expired", "urgent", "soon"])
    }

    @Test func tiersGroupBySeverityAndDropEmpty() async throws {
        let store = try await makeStore([
            item(id: "expired", name: "菠菜", state: .expired),
            item(id: "soon1", name: "酸奶", state: .expiringSoon),
            item(id: "soon2", name: "牛奶", state: .expiringSoon),
            // no urgent items → that tier must be dropped
        ])
        let tiers = store.tiers
        #expect(tiers.map(\.state) == [.expired, .expiringSoon])
        #expect(tiers.first?.items.map(\.id) == ["expired"])
        #expect(tiers.last?.items.count == 2)
    }

    @Test func healthyPantryHasNoTiers() async throws {
        let store = try await makeStore([
            item(id: "f1", name: "苹果", state: .fresh),
            item(id: "f2", name: "酱油", state: .fresh),
        ])
        #expect(store.sortedItems.isEmpty)
        #expect(store.tiers.isEmpty)
    }
}
