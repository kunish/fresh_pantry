import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// SwiftData round-trips through the repositories in an in-memory container,
/// covering the parity-critical persistence invariants.
struct RepositoryTests {
    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    private func ingredient(id: String = "", name: String, quantity: String = "1", unit: String = "份") -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: quantity, unit: unit, imageUrl: "",
            freshnessPercent: 1.0, state: .fresh
        )
    }

    // MARK: Inventory

    @Test func inventorySaveAndLoadRoundTrip() async throws {
        let repo = InventoryRepository(modelContainer: try container())
        let items = [
            ingredient(id: "ing_1", name: "牛奶"),
            ingredient(id: "ing_2", name: "鸡蛋"),
        ]
        try await repo.saveItems("home", items)
        let loaded = try await repo.loadAllFor("home")
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.id)) == ["ing_1", "ing_2"])
    }

    @Test func inventoryBlankIdsRepeatButRealIdsDedup() async throws {
        let repo = InventoryRepository(modelContainer: try container())
        // Two blank-id local rows (must both survive) + duplicate real id (collapse).
        try await repo.saveItems("home", [
            ingredient(id: "", name: "A"),
            ingredient(id: "", name: "B"),
            ingredient(id: "ing_x", name: "C"),
            ingredient(id: "ing_x", name: "C-dup"),
        ])
        let loaded = try await repo.loadAllFor("home")
        let blankCount = loaded.filter { $0.id.isEmpty }.count
        let realCount = loaded.filter { $0.id == "ing_x" }.count
        #expect(blankCount == 2) // blank ids legitimately repeat
        #expect(realCount == 1)  // non-empty id unique within household
    }

    @Test func inventoryHouseholdScopeIsolated() async throws {
        let repo = InventoryRepository(modelContainer: try container())
        try await repo.saveItems("home", [ingredient(id: "h1", name: "X")])
        try await repo.saveItems("work", [ingredient(id: "w1", name: "Y")])
        #expect(try await repo.loadAllFor("home").map(\.id) == ["h1"])
        #expect(try await repo.loadAllFor("work").map(\.id) == ["w1"])
        // Saving "home" again must not wipe "work".
        try await repo.saveItems("home", [ingredient(id: "h2", name: "Z")])
        #expect(try await repo.loadAllFor("work").map(\.id) == ["w1"])
    }

    @Test func inventoryAddHistoryAndFrequentItems() async throws {
        let repo = InventoryRepository(modelContainer: try container())
        let milk = ingredient(name: "牛奶", unit: "盒")
        try await repo.recordAddition(milk)
        try await repo.recordAddition(milk)
        let frequent = try await repo.loadFrequentItems()
        #expect(frequent.count == 1)
        #expect(frequent[0].name == "牛奶")
        #expect(frequent[0].count == 2)
        #expect(frequent[0].unit == "盒")
        // forget removes it.
        try await repo.forgetAddition("牛奶")
        #expect(try await repo.loadFrequentItems().isEmpty)
    }

    @Test func recordAdditionsBatchesCountsIncludingRepeats() async throws {
        let repo = InventoryRepository(modelContainer: try container())
        // ONE batched read+write: a repeated name accumulates (牛奶 ×2), distinct
        // names count 1 — replaces the old O(N²) per-item whole-history rewrite.
        try await repo.recordAdditions([
            ingredient(name: "牛奶", unit: "盒"),
            ingredient(name: "鸡蛋"),
            ingredient(name: "牛奶", unit: "盒"),
        ])
        let byName = Dictionary(
            uniqueKeysWithValues: try await repo.loadFrequentItems().map { ($0.name, $0.count) }
        )
        #expect(byName["牛奶"] == 2)
        #expect(byName["鸡蛋"] == 1)
        // The single `recordAddition` is now a shim over the batch — still bumps.
        try await repo.recordAddition(ingredient(name: "鸡蛋"))
        #expect(try await repo.loadFrequentItems().first { $0.name == "鸡蛋" }?.count == 2)
    }

    // MARK: Shopping (dedup on load)

    @Test func shoppingDedupOnLoad() async throws {
        let container = try container()
        // Insert two case-insensitive name dups directly (bypass save-side dedup).
        let context = ModelContext(container)
        context.insert(ShoppingItemRecord(
            householdID: "home",
            item: ShoppingItem(id: "si_1", name: "牛奶", detail: "1", category: "其他")))
        context.insert(ShoppingItemRecord(
            householdID: "home",
            item: ShoppingItem(id: "si_2", name: "牛奶", detail: "2", category: "其他")))
        try context.save()

        let repo = ShoppingRepository(modelContainer: container)
        let loaded = try await repo.loadAllFor("home")
        #expect(loaded.count == 1) // case-insensitive name dedup keeps first
        #expect(loaded[0].id == "si_1")
    }

    // MARK: Shopping single-row primitives (the offline-first optimistic path)

    private func shopItem(_ id: String, _ name: String, checked: Bool = false, detail: String = "") -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: detail, category: "其他", isChecked: checked)
    }

    @Test func shoppingUpdateRowEditsOnlyThatRowAndLeavesPeers() async throws {
        let repo = ShoppingRepository(modelContainer: try container())
        try await repo.saveItems("home", [shopItem("a", "牛奶"), shopItem("b", "鸡蛋")])
        // Update only "a" — "b" (a peer's row) must be untouched.
        let did = try await repo.updateRow("home", shopItem("a", "牛奶", checked: true))
        #expect(did)
        let rows = try await repo.loadAllFor("home")
        #expect(rows.first { $0.id == "a" }?.isChecked == true)
        #expect(rows.first { $0.id == "b" }?.isChecked == false)
        #expect(rows.count == 2) // no clobber
    }

    @Test func shoppingUpdateRowReturnsFalseWhenAbsentAndDoesNotInsert() async throws {
        let repo = ShoppingRepository(modelContainer: try container())
        try await repo.saveItems("home", [shopItem("a", "牛奶")])
        // The row a peer already deleted: update must be a no-op, NOT a resurrect.
        let did = try await repo.updateRow("home", shopItem("zzz", "幽灵", checked: true))
        #expect(!did)
        #expect(try await repo.loadAllFor("home").map(\.id) == ["a"])
    }

    @Test func shoppingUpsertInsertsThenUpdatesInPlace() async throws {
        let repo = ShoppingRepository(modelContainer: try container())
        try await repo.upsert("home", shopItem("a", "牛奶", detail: "1 盒"))
        #expect(try await repo.loadAllFor("home").map(\.id) == ["a"])
        // Same id again updates in place (no duplicate row).
        try await repo.upsert("home", shopItem("a", "牛奶", detail: "3 盒"))
        let rows = try await repo.loadAllFor("home")
        #expect(rows.count == 1)
        #expect(rows[0].detail == "3 盒")
    }

    @Test func shoppingDeleteByIdsRemovesOnlyTargets() async throws {
        let repo = ShoppingRepository(modelContainer: try container())
        try await repo.saveItems("home", [shopItem("a", "牛奶"), shopItem("b", "鸡蛋"), shopItem("c", "苹果")])
        try await repo.delete("home", ids: ["a", "c", "ghost"]) // ghost is a no-op
        #expect(try await repo.loadAllFor("home").map(\.id) == ["b"])
    }

    @Test func shoppingSingleRowWritesAreHouseholdScoped() async throws {
        let repo = ShoppingRepository(modelContainer: try container())
        try await repo.saveItems("home", [shopItem("h", "X")])
        try await repo.saveItems("work", [shopItem("w", "Y")])
        // A "home" upsert/delete must never reach the "work" scope.
        try await repo.upsert("home", shopItem("h", "X", checked: true))
        try await repo.delete("home", ids: ["h"])
        #expect(try await repo.loadAllFor("home").isEmpty)
        #expect(try await repo.loadAllFor("work").map(\.id) == ["w"])
    }

    // MARK: MealPlan single-row primitives

    @Test func mealPlanSingleRowPrimitivesTouchOnlyTarget() async throws {
        let repo = MealPlanRepository(modelContainer: try container())
        let day = MealPlanEntry.parseDate("2026-06-08")!
        func entry(_ id: String, done: Bool = false) -> MealPlanEntry {
            MealPlanEntry(id: id, date: day, recipeId: "r", recipeName: "n", done: done)
        }
        try await repo.upsert("home", entry("a"))
        try await repo.upsert("home", entry("b"))
        // updateRow flips only "a".
        #expect(try await repo.updateRow("home", entry("a", done: true)))
        // updateRow on an absent id is a no-op, not an insert.
        #expect(!(try await repo.updateRow("home", entry("zzz", done: true))))
        // delete(ids:) removes only "b".
        try await repo.delete("home", ids: ["b"])
        let rows = try await repo.loadAllFor("home")
        #expect(rows.map(\.id) == ["a"])
        #expect(rows[0].done == true)
    }

    // MARK: MealPlan (dirty row skipped)

    @Test func mealPlanSkipsDirtyDateRow() async throws {
        let container = try container()
        let context = ModelContext(container)
        // Hand-craft a record whose payload has an unparseable date.
        let bad = MealPlanRecord(
            householdID: "home",
            entry: MealPlanEntry(
                id: "ok", date: MealPlanEntry.parseDate("2026-06-08")!,
                recipeId: "r", recipeName: "n"))
        bad.id = "bad"
        bad.payloadJSON = #"{"id":"bad","recipeId":"r","date":"garbage"}"#
        context.insert(bad)
        let good = MealPlanRecord(
            householdID: "home",
            entry: MealPlanEntry(
                id: "ok", date: MealPlanEntry.parseDate("2026-06-08")!,
                recipeId: "r", recipeName: "n"))
        context.insert(good)
        try context.save()

        let repo = MealPlanRepository(modelContainer: container)
        let loaded = try await repo.loadAllFor("home")
        #expect(loaded.map(\.id) == ["ok"]) // dirty row skipped, rest preserved
    }

    // MARK: FoodLog (point-delete vs saveEntries distinct)

    @Test func foodLogAppendNoOpOnBlankId() async throws {
        let repo = FoodLogRepository(modelContainer: try container())
        let loggedAt = JSONDate.parse("2026-06-08T10:00:00Z")!
        try await repo.append("home", FoodLogEntry(id: "", name: "x", outcome: .consumed, loggedAt: loggedAt))
        #expect(try await repo.loadAllFor("home").isEmpty) // blank id never written
    }

    @Test func foodLogPointDeleteKeepsOthers() async throws {
        let repo = FoodLogRepository(modelContainer: try container())
        let t = JSONDate.parse("2026-06-08T10:00:00Z")!
        try await repo.append("home", FoodLogEntry(id: "fl_1", name: "a", outcome: .consumed, loggedAt: t))
        try await repo.append("home", FoodLogEntry(id: "fl_2", name: "b", outcome: .wasted, loggedAt: t))
        try await repo.deleteEntry("home", "fl_1")
        let loaded = try await repo.loadAllFor("home")
        #expect(loaded.map(\.id) == ["fl_2"]) // only the targeted row removed
    }

    @Test func migrateLegacyFoodLogIdsRewritesPrefixedRowsAndIsIdempotent() async throws {
        let repo = FoodLogRepository(modelContainer: try container())
        let t = JSONDate.parse("2026-06-08T10:00:00Z")!
        try await repo.append("home", FoodLogEntry(id: "fl_1", name: "牛奶", outcome: .consumed, loggedAt: t))
        let keep = FoodLogEntry(id: "11111111-1111-4111-8111-111111111111", name: "番茄", outcome: .wasted, loggedAt: t)
        try await repo.append("home", keep)

        let changed = try await repo.migrateLegacyIds()
        #expect(changed == 1) // only the fl_ row

        let loaded = try await repo.loadAllFor("home")
        let ids = Set(loaded.map(\.id))
        #expect(!ids.contains("fl_1")) // old id gone
        #expect(ids.contains(keep.id)) // uuid row untouched
        let migrated = try #require(loaded.first { $0.name == "牛奶" })
        #expect(UUID(uuidString: migrated.id) != nil) // new id is a uuid
        #expect(migrated.outcome == .consumed) // other fields intact
        #expect(migrated.loggedAt == t)

        let again = try await repo.migrateLegacyIds()
        #expect(again == 0) // idempotent
    }

    @Test func foodLogRecentWindowFilter() async throws {
        let repo = FoodLogRepository(modelContainer: try container())
        let old = JSONDate.parse("2026-01-01T00:00:00Z")!
        let recent = JSONDate.parse("2026-06-08T00:00:00Z")!
        try await repo.append("home", FoodLogEntry(id: "old", name: "a", outcome: .consumed, loggedAt: old))
        try await repo.append("home", FoodLogEntry(id: "new", name: "b", outcome: .consumed, loggedAt: recent))
        let sinceMs = Int(JSONDate.parse("2026-06-01T00:00:00Z")!.timeIntervalSince1970 * 1000)
        let loaded = try await repo.loadRecentFor("home", sinceMs: sinceMs)
        #expect(loaded.map(\.id) == ["new"])
    }

    // MARK: CustomRecipe (id+name guard)

    @Test func customRecipeFiltersEmptyIdOrName() async throws {
        let repo = CustomRecipeRepository(modelContainer: try container())
        try await repo.saveRecipes("home", [
            Recipe(id: "ok", name: "番茄炒蛋", category: "家常", difficulty: 1,
                   cookingMinutes: 15, description: "", ingredients: [], steps: []),
            Recipe(id: "", name: "noid", category: "", difficulty: 0,
                   cookingMinutes: 30, description: "", ingredients: [], steps: []),
            Recipe(id: "noname", name: "", category: "", difficulty: 0,
                   cookingMinutes: 30, description: "", ingredients: [], steps: []),
        ])
        let loaded = try await repo.loadAllFor("home")
        #expect(loaded.map(\.id) == ["ok"])
    }

    // MARK: SyncOutbox

    @Test func syncOutboxEnqueueAndRemove() async throws {
        let repo = SyncOutboxRepository(modelContainer: try container())
        let op = SyncOperation(
            id: "op_1", householdId: "home", entityType: .inventoryItem,
            entityId: "ing_1", operation: .create, patch: ["name": .string("牛奶")],
            clientId: "client", createdAt: Date(timeIntervalSince1970: 1000))
        try await repo.enqueue(op)
        #expect(try await repo.pendingCount() == 1)
        let pending = try await repo.loadPending()
        #expect(pending.first?.patch["name"] == .string("牛奶"))
        try await repo.removeAcknowledged(["op_1"])
        #expect(try await repo.pendingCount() == 0)
    }
}
