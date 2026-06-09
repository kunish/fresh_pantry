import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the household-management store's pure / local-only bits that
/// don't need live creds: the adoption helper (move `""` rows into the household
/// scope + clear `""`, re-minting non-UUID ids), the `selectedHousehold`
/// derivation, and the selection-pick rules. The store is built with `remote: nil`
/// so the network methods are skipped; only the local-data + pure logic runs.
@MainActor
struct HouseholdSessionStoreTests {
    // MARK: Fixtures

    /// Builds a store with real in-memory repos and no backend (local-only).
    private func makeStore(
        session: SyncSession = SyncSession(selectedHouseholdId: "")
    ) throws -> (store: HouseholdSessionStore, repos: Repos) {
        let container = try ModelContainerFactory.makeInMemory()
        let repos = Repos(
            inventory: InventoryRepository(modelContainer: container),
            shopping: ShoppingRepository(modelContainer: container),
            customRecipe: CustomRecipeRepository(modelContainer: container),
            mealPlan: MealPlanRepository(modelContainer: container)
        )
        let store = HouseholdSessionStore(
            remote: nil,
            session: session,
            auth: AuthService(backend: nil),
            inventory: repos.inventory,
            shopping: repos.shopping,
            customRecipe: repos.customRecipe,
            mealPlan: repos.mealPlan
        )
        return (store, repos)
    }

    private struct Repos {
        let inventory: InventoryRepository
        let shopping: ShoppingRepository
        let customRecipe: CustomRecipeRepository
        let mealPlan: MealPlanRepository
    }

    private func ingredient(id: String, name: String) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other, storage: .fridge
        )
    }

    private func shoppingItem(id: String, name: String) -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: "1 份", category: FoodCategories.other)
    }

    private func recipe(id: String, name: String) -> Recipe {
        Recipe(
            id: id, name: name, category: "家常", difficulty: 1, cookingMinutes: 10,
            description: "", ingredients: [RecipeIngredient(name: "盐")], steps: ["炒"]
        )
    }

    private func mealPlanEntry(id: String, recipe: String) -> MealPlanEntry {
        MealPlanEntry(id: id, date: Date(), recipeId: "r1", recipeName: recipe)
    }

    private let uuid = "11111111-1111-4111-8111-111111111111"

    // MARK: Adoption

    @Test func adoptMovesAllScopesIntoHouseholdAndClearsLocal() async throws {
        let (store, repos) = try makeStore()
        try await repos.inventory.saveItems("", [ingredient(id: uuid, name: "牛奶")])
        try await repos.shopping.saveItems("", [shoppingItem(id: uuid, name: "鸡蛋")])
        try await repos.customRecipe.saveRecipes("", [recipe(id: uuid, name: "番茄炒蛋")])
        try await repos.mealPlan.saveEntries("", [mealPlanEntry(id: uuid, recipe: "番茄炒蛋")])

        await store.adoptLocalDataIntoHousehold("home")

        // Moved into the household scope.
        #expect(try await repos.inventory.loadAllFor("home").count == 1)
        #expect(try await repos.shopping.loadAllFor("home").count == 1)
        #expect(try await repos.customRecipe.loadAllFor("home").count == 1)
        #expect(try await repos.mealPlan.loadAllFor("home").count == 1)

        // Personal ('') scope purged.
        #expect(try await repos.inventory.loadAllFor("").isEmpty)
        #expect(try await repos.shopping.loadAllFor("").isEmpty)
        #expect(try await repos.customRecipe.loadAllFor("").isEmpty)
        #expect(try await repos.mealPlan.loadAllFor("").isEmpty)
    }

    @Test func adoptKeepsUuidIdsAndRemintsNonUuidIds() async throws {
        let (store, repos) = try makeStore()
        // A valid UUID is kept; a non-UUID `si_…` id is re-minted to a fresh UUID.
        try await repos.shopping.saveItems("", [
            shoppingItem(id: uuid, name: "鸡蛋"),
            shoppingItem(id: "si_12345", name: "面包"),
        ])

        await store.adoptLocalDataIntoHousehold("home")

        let moved = try await repos.shopping.loadAllFor("home")
        #expect(moved.count == 2)
        let movedIds = Set(moved.map(\.id))
        // The valid UUID survives unchanged.
        #expect(movedIds.contains(uuid))
        // The non-UUID id was re-minted to a canonical UUID (not the original).
        #expect(!movedIds.contains("si_12345"))
        #expect(moved.allSatisfy { ProposalApply.isUuid($0.id) })
    }

    @Test func adoptIntoEmptyHouseholdIsNoOp() async throws {
        let (store, repos) = try makeStore()
        try await repos.inventory.saveItems("", [ingredient(id: uuid, name: "牛奶")])

        // Empty id must never purge the personal scope (guard mirrors Dart).
        await store.adoptLocalDataIntoHousehold("")

        #expect(try await repos.inventory.loadAllFor("").count == 1)
    }

    @Test func adoptWithNoLocalDataLeavesScopesEmpty() async throws {
        let (store, repos) = try makeStore()
        await store.adoptLocalDataIntoHousehold("home")
        #expect(try await repos.inventory.loadAllFor("home").isEmpty)
        #expect(try await repos.shopping.loadAllFor("home").isEmpty)
    }

    // MARK: Derived state

    @Test func isConfiguredFalseWithoutRemote() throws {
        let (store, _) = try makeStore()
        #expect(store.isConfigured == false)
    }

    @Test func selectedHouseholdResolvesFromSessionScope() throws {
        let session = SyncSession(selectedHouseholdId: "h2")
        let (store, _) = try makeStore(session: session)
        // No households loaded → nil even with a selected id.
        #expect(store.selectedHousehold == nil)
    }

    // MARK: Selection pick rules

    private func household(_ id: String) -> Household {
        Household(id: id, name: "H\(id)", ownerId: "o", defaultStorageArea: "fridge")
    }

    @Test func pickSelectedKeepsCurrentWhenStillJoined() {
        let hs = [household("a"), household("b")]
        #expect(HouseholdSessionStore.pickSelected(hs, current: "b") == "b")
    }

    @Test func pickSelectedFallsBackToFirstThenEmpty() {
        let hs = [household("a"), household("b")]
        // Current no longer joined → first.
        #expect(HouseholdSessionStore.pickSelected(hs, current: "gone") == "a")
        // Empty list → "".
        #expect(HouseholdSessionStore.pickSelected([], current: "a") == "")
    }

    @Test func pickJoinedPrefersPreferredThenCurrentThenLast() {
        let hs = [household("a"), household("b"), household("c")]
        // Preferred wins.
        #expect(HouseholdSessionStore.pickJoined(hs, preferred: "b", current: "a") == "b")
        // Preferred absent → keep current if present.
        #expect(HouseholdSessionStore.pickJoined(hs, preferred: "gone", current: "a") == "a")
        // Neither preferred nor current present → LAST.
        #expect(HouseholdSessionStore.pickJoined(hs, preferred: nil, current: "gone") == "c")
        #expect(HouseholdSessionStore.pickJoined([], preferred: "x", current: "y") == "")
    }

    @Test func pickAfterRemovalKeepsSurvivorElseFirst() {
        let hs = [household("a"), household("b")]
        // Current survived and wasn't removed → keep.
        #expect(HouseholdSessionStore.pickAfterRemoval(hs, removed: "z", current: "b") == "b")
        // Current was the removed one → first survivor.
        #expect(HouseholdSessionStore.pickAfterRemoval(hs, removed: "b", current: "b") == "a")
        // No survivors → "".
        #expect(HouseholdSessionStore.pickAfterRemoval([], removed: "b", current: "b") == "")
    }
}
