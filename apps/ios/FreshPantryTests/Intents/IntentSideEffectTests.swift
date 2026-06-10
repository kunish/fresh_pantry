import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Side-effect tests against REAL in-memory SwiftData: the query reader's
/// cross-scope + soft-delete-excluding fetch, and the add drainer landing a row
/// (with a recorded outbox op) through a live `ShoppingStore` — mirroring the
/// intent → app handoff without the AppIntents runtime.
@MainActor
struct IntentSideEffectTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    private func ingredient(_ name: String, expiresInDays days: Int, now: Date, deleted: Bool = false) -> Ingredient {
        let expiry = Calendar.current.date(byAdding: .day, value: days, to: now)!
        return Ingredient(
            id: name, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other,
            storage: .fridge, expiryDate: expiry,
            deletedAt: deleted ? now : nil
        )
    }

    // MARK: - IntentInventoryReader

    @Test func readerLoadsAcrossHouseholdScopes() async throws {
        let container = try makeContainer()
        let repo = InventoryRepository(modelContainer: container)
        let now = Date()
        // Two different household scopes both present in the local container.
        try await repo.saveItems("home", [ingredient("牛奶", expiresInDays: 1, now: now)])
        try await repo.saveItems("family", [ingredient("鸡蛋", expiresInDays: 2, now: now)])

        let reader = IntentInventoryReader(modelContainer: container)
        let names = Set((try await reader.loadAllLive(now: now)).map(\.name))
        #expect(names == ["牛奶", "鸡蛋"])
    }

    @Test func readerExcludesSoftDeletedRows() async throws {
        let container = try makeContainer()
        let repo = InventoryRepository(modelContainer: container)
        let now = Date()
        try await repo.saveItems("home", [
            ingredient("牛奶", expiresInDays: 1, now: now),
            ingredient("旧奶", expiresInDays: 1, now: now, deleted: true),
        ])

        let reader = IntentInventoryReader(modelContainer: container)
        let names = (try await reader.loadAllLive(now: now)).map(\.name)
        #expect(names == ["牛奶"])
    }

    @Test func readerFeedsExpiringSelectorEndToEnd() async throws {
        let container = try makeContainer()
        let repo = InventoryRepository(modelContainer: container)
        let now = Date()
        try await repo.saveItems("home", [
            ingredient("牛奶", expiresInDays: 1, now: now),
            ingredient("罐头", expiresInDays: 30, now: now),
        ])

        let reader = IntentInventoryReader(modelContainer: container)
        let items = try await reader.loadAllLive(now: now)
        #expect(ExpiringFoodSelector.expiringNames(in: items, now: now) == ["牛奶"])
    }

    // MARK: - IntentAddDrainer

    @Test func drainerAddsQueuedNamesToShoppingScope() async throws {
        let container = try makeContainer()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        let queue = IntentPendingAddQueue(defaults: UserDefaults(suiteName: "test.drainer.\(UUID().uuidString)")!)
        queue.enqueue("牛奶")
        queue.enqueue("鸡蛋")

        await IntentAddDrainer.drain(dependencies: dependencies, queue: queue)

        // Both rows landed in the household's shopping scope.
        let rows = try await dependencies.shoppingRepository.loadAllFor("home")
        #expect(Set(rows.map(\.name)) == ["牛奶", "鸡蛋"])
        // Queue consumed (a second drain is a no-op).
        #expect(queue.peek() == [])
    }

    @Test func drainerEnqueuesOutboxOpsForSync() async throws {
        let container = try makeContainer()
        // Non-empty household → SyncWriter records ops (coordinator nil → no push).
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        let queue = IntentPendingAddQueue(defaults: UserDefaults(suiteName: "test.drainer.\(UUID().uuidString)")!)
        queue.enqueue("牛奶")

        await IntentAddDrainer.drain(dependencies: dependencies, queue: queue)

        // The add went through the real outbox path so it syncs to the family.
        let pending = try await dependencies.syncOutboxRepository.loadPending()
        #expect(pending.contains { $0.entityType == .shoppingItem && $0.operation == .create })
    }

    @Test func drainerConsumesDuplicateWithoutRequeueing() async throws {
        // A name already on the list makes `ShoppingStore.add` return false (a
        // detail-less duplicate can't merge). That is the user's "已在清单中"
        // outcome, NOT a write failure — the drainer must consume it so it does
        // not re-queue the same name forever.
        let container = try makeContainer()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        try await dependencies.shoppingRepository.saveItems("home", [
            ShoppingItem(id: "s1", name: "牛奶", detail: "", category: FoodCategories.other),
        ])
        let queue = IntentPendingAddQueue(defaults: UserDefaults(suiteName: "test.drainer.\(UUID().uuidString)")!)
        queue.enqueue("牛奶")

        await IntentAddDrainer.drain(dependencies: dependencies, queue: queue)

        #expect(queue.peek() == []) // consumed, not re-queued
        let rows = try await dependencies.shoppingRepository.loadAllFor("home")
        #expect(rows.filter { $0.name == "牛奶" }.count == 1) // no duplicate row
    }

    @Test func drainerOnEmptyQueueIsNoOp() async throws {
        let container = try makeContainer()
        let dependencies = AppDependencies(modelContainer: container, householdID: "home")
        let queue = IntentPendingAddQueue(defaults: UserDefaults(suiteName: "test.drainer.\(UUID().uuidString)")!)

        await IntentAddDrainer.drain(dependencies: dependencies, queue: queue)

        #expect(try await dependencies.shoppingRepository.loadAllFor("home").isEmpty)
        #expect(try await dependencies.syncOutboxRepository.pendingCount() == 0)
    }
}
