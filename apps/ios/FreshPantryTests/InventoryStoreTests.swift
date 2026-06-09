import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Inventory feature store: urgency sort, storage filter,
/// name search, and delete. Backed by a real in-memory repository so the load /
/// persist path is exercised end-to-end.
@MainActor
struct InventoryStoreTests {
    private func makeStore(_ items: [Ingredient], household: String = "home") async throws -> InventoryStore {
        try await makeStoreWithLog(items, household: household).store
    }

    /// Builds a store backed by real in-memory inventory + food-log repos, and
    /// returns the food-log repo too so the removal-with-outcome tests can assert
    /// the logged departure (and its reversal on undo).
    private func makeStoreWithLog(
        _ items: [Ingredient],
        household: String = "home"
    ) async throws -> (store: InventoryStore, log: FoodLogRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let store = InventoryStore(repository: repo, foodLogRepository: log, householdID: household)
        await store.load()
        return (store, log)
    }

    /// Stable, expiry-free item so its state isn't recomputed by the loader's
    /// freshness normalization (no expiry date → state preserved as given).
    private func item(
        id: String,
        name: String,
        state: FreshnessState,
        storage: IconType = .fridge,
        category: String? = nil
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: state, category: category, storage: storage
        )
    }

    /// Item with an explicit expiry offset (drives loader-recomputed urgency).
    private func dated(id: String, name: String, daysUntilExpiry: Int, shelfLife: Int = 30) -> Ingredient {
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .day, value: daysUntilExpiry, to: now)!
        return Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other,
            storage: .pantry, expiryDate: expiry, addedAt: now, shelfLifeDays: shelfLife
        )
    }

    // MARK: Loading

    @Test func loadPopulatesItemsAndSetsFlags() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        #expect(store.items.count == 1)
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    // MARK: Urgency sort

    @Test func displayItemsSortByUrgencyMostSevereFirst() async throws {
        let store = try await makeStore([
            item(id: "fresh", name: "苹果", state: .fresh),
            item(id: "expired", name: "菠菜", state: .expired),
            item(id: "soon", name: "酸奶", state: .expiringSoon),
            item(id: "urgent", name: "鸡肉", state: .urgent),
        ])
        // expired → urgent → expiringSoon → fresh
        #expect(store.displayItems.map(\.id) == ["expired", "urgent", "soon", "fresh"])
    }

    @Test func sameTierSortsBySoonestExpiryFirst() async throws {
        // Both land in `.fresh` (far-out expiry); soonest expiry sorts first.
        let store = try await makeStore([
            dated(id: "later", name: "B", daysUntilExpiry: 25),
            dated(id: "sooner", name: "A", daysUntilExpiry: 20),
        ])
        #expect(store.displayItems.map(\.id) == ["sooner", "later"])
    }

    @Test func derivingDisplayItemsDoesNotMutateSourceList() async throws {
        let store = try await makeStore([
            item(id: "fresh", name: "苹果", state: .fresh),
            item(id: "expired", name: "菠菜", state: .expired),
        ])
        let before = store.items.map(\.id)
        _ = store.displayItems // urgency sort must not touch the source list
        _ = store.displayItems // idempotent
        #expect(store.items.map(\.id) == before) // source order untouched by derivation
        // And display order IS reordered (expired first), proving sort is display-only.
        #expect(store.displayItems.map(\.id) == ["expired", "fresh"])
    }

    // MARK: Storage filter

    @Test func storageFilterRestrictsToArea() async throws {
        let store = try await makeStore([
            item(id: "f1", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "z1", name: "三文鱼", state: .fresh, storage: .freezer),
            item(id: "p1", name: "酱油", state: .fresh, storage: .pantry),
        ])
        store.storageFilter = .area(.freezer)
        #expect(store.displayItems.map(\.id) == ["z1"])
        store.storageFilter = .all
        #expect(store.displayItems.count == 3)
    }

    @Test func storageCountsPerArea() async throws {
        let store = try await makeStore([
            item(id: "f1", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "f2", name: "鸡蛋", state: .fresh, storage: .fridge),
            item(id: "p1", name: "盐", state: .fresh, storage: .pantry),
        ])
        #expect(store.count(for: .all) == 3)
        #expect(store.count(for: .area(.fridge)) == 2)
        #expect(store.count(for: .area(.pantry)) == 1)
        #expect(store.count(for: .area(.freezer)) == 0)
    }

    // MARK: Search

    @Test func searchMatchesNameCaseInsensitively() async throws {
        let store = try await makeStore([
            item(id: "a", name: "Salmon", state: .fresh),
            item(id: "b", name: "牛奶", state: .fresh),
        ])
        store.searchQuery = "  SALM "
        #expect(store.displayItems.map(\.id) == ["a"])
    }

    @Test func searchAndStorageFilterCompose() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh, storage: .fridge),
            item(id: "b", name: "牛肉", state: .fresh, storage: .freezer),
        ])
        store.searchQuery = "牛"
        store.storageFilter = .area(.fridge)
        #expect(store.displayItems.map(\.id) == ["a"]) // both name-match, storage narrows
    }

    @Test func hasActiveQueryReflectsFilterAndSearch() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        #expect(!store.hasActiveQuery)
        store.searchQuery = "牛"
        #expect(store.hasActiveQuery)
        store.searchQuery = ""
        store.storageFilter = .area(.fridge)
        #expect(store.hasActiveQuery)
    }

    // MARK: Delete

    @Test func deleteRemovesByIdAndPersists() async throws {
        let store = try await makeStore([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!
        let removed = await store.delete(target)
        #expect(removed)
        #expect(store.items.map(\.id) == ["b"])

        // Survives a reload (persisted, not just local mutation).
        await store.load()
        #expect(store.items.map(\.id) == ["b"])
    }

    @Test func deleteUnknownItemReturnsFalse() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", state: .fresh)])
        let ghost = item(id: "zzz", name: "幽灵", state: .fresh)
        let removed = await store.delete(ghost)
        #expect(!removed)
        #expect(store.items.count == 1)
    }

    // MARK: Remove-with-outcome (manual-removal waste-stats log path)

    @Test func removeConsumedLogsConsumedDepartureAndRemovesRow() async throws {
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh, category: FoodCategories.dairyAndEggs),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        let target = store.items.first { $0.id == "a" }!

        let undo = await store.remove(target, outcome: .consumed)
        #expect(undo != nil)
        #expect(store.items.map(\.id) == ["b"]) // row removed
        await store.load()
        #expect(store.items.map(\.id) == ["b"]) // persisted

        let entries = try await log.loadAllFor("home")
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.name == "牛奶")
        #expect(entry.outcome == .consumed)
        #expect(entry.category == FoodCategories.dairyAndEggs) // snapshot
        #expect(!entry.wasExpiring) // fresh → false
    }

    @Test func removeWastedSnapshotsWasExpiringFromNonFreshState() async throws {
        // An urgent (non-fresh) row removed as 扔掉了 must log wasted + wasExpiring.
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "三文鱼", state: .urgent, category: FoodCategories.meatAndSeafood),
        ])
        let target = store.items.first { $0.id == "a" }!

        let undo = await store.remove(target, outcome: .wasted)
        #expect(undo != nil)

        let entry = try #require(try await log.loadAllFor("home").first)
        #expect(entry.outcome == .wasted)
        #expect(entry.wasExpiring) // urgent → not fresh → true
    }

    @Test func removeUnknownItemDoesNotLog() async throws {
        let (store, log) = try await makeStoreWithLog([item(id: "a", name: "牛奶", state: .fresh)])
        let ghost = item(id: "zzz", name: "幽灵", state: .fresh)

        let undo = await store.remove(ghost, outcome: .consumed)
        #expect(undo == nil)
        #expect(store.items.count == 1)
        let entries = try await log.loadAllFor("home")
        #expect(entries.isEmpty) // nothing matched → nothing logged
    }

    @Test func undoRemoveReAddsRowAndReversesLogViaPointDelete() async throws {
        // The undo MUST reverse BOTH sides: the row returns and the logged
        // departure is point-deleted (NOT a saveEntries replace-all).
        let (store, log) = try await makeStoreWithLog([
            item(id: "a", name: "牛奶", state: .fresh),
            item(id: "b", name: "鸡蛋", state: .fresh),
        ])
        // Pre-seed an UNRELATED out-of-band food-log entry; a correct undo (point
        // delete) must leave it intact (a saveEntries replace-all would drop it).
        let survivor = FoodLogEntry(
            id: "fl_survivor", name: "苹果", outcome: .consumed, loggedAt: Date()
        )
        try await log.append("home", survivor)

        let target = store.items.first { $0.id == "a" }!
        let undo = try #require(await store.remove(target, outcome: .wasted))
        #expect(store.items.map(\.id) == ["b"]) // row gone
        #expect(try await log.loadAllFor("home").count == 2) // survivor + new

        let reversed = await store.undoRemove(undo)
        #expect(reversed)
        // The row is back (order-agnostic — the repo fetch is unordered).
        #expect(store.items.map(\.id).sorted() == ["a", "b"])
        await store.load()
        #expect(store.items.map(\.id).sorted() == ["a", "b"]) // persisted

        // The logged departure is gone, but the unrelated survivor remains —
        // proving a point-delete, not a saveEntries replace-all (which would have
        // dropped the survivor too).
        let remaining = try await log.loadAllFor("home")
        #expect(remaining.map(\.id) == ["fl_survivor"])
    }

    // MARK: Household re-scoping

    /// Regression for the live-sync bug where a feature view built its store ONCE
    /// and never rebuilt it on a household change, so the list kept showing the old
    /// scope's rows. The fix rebuilds the store with the current `householdID`; this
    /// asserts the underlying invariant — a store built for household B loads B's
    /// rows, not A's — against a single shared repository (the two scopes are
    /// disjoint).
    @Test func storeRebuiltForNewHouseholdLoadsThatScope() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = InventoryRepository(modelContainer: container)
        let log = FoodLogRepository(modelContainer: container)
        try await repo.saveItems("home-a", [item(id: "a", name: "牛奶", state: .fresh)])
        try await repo.saveItems("home-b", [item(id: "b", name: "鸡蛋", state: .fresh)])

        // The store the view built for the first scope.
        let storeA = InventoryStore(repository: repo, foodLogRepository: log, householdID: "home-a")
        await storeA.load()
        #expect(storeA.items.map(\.id) == ["a"])

        // After the household switches, `.task(id:)` rebuilds the store for the new
        // scope — it must surface B's rows, never A's.
        let storeB = InventoryStore(repository: repo, foodLogRepository: log, householdID: "home-b")
        await storeB.load()
        #expect(storeB.items.map(\.id) == ["b"])
    }
}
