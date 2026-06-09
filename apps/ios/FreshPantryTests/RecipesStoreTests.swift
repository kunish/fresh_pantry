import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the Recipes feature store: bundled+custom merge (custom
/// wins on id), category filter, name/ingredient search, favorites-only filter,
/// derived category options, and the stale-category auto-clear invariant.
@MainActor
struct RecipesStoreTests {
    // MARK: Builders

    private func recipe(
        id: String,
        name: String,
        category: String,
        difficulty: Int = 2,
        minutes: Int = 20,
        ingredients: [RecipeIngredient] = [],
        description: String = ""
    ) -> Recipe {
        Recipe(
            id: id, name: name, category: category, difficulty: difficulty,
            cookingMinutes: minutes, description: description,
            ingredients: ingredients, steps: []
        )
    }

    /// Builds a store seeded with a stub bundled corpus (via an injected custom
    /// repo carrying the "bundled" set so we can drive load without the real
    /// asset) — but here we exercise the pure merge/filter logic directly.
    private func makeStore(
        bundled: [Recipe],
        custom: [Recipe] = [],
        household: String = "home"
    ) async throws -> RecipesStore {
        let container = try ModelContainerFactory.makeInMemory()
        let customRepo = CustomRecipeRepository(modelContainer: container)
        try await customRepo.saveRecipes(household, custom)
        let store = RecipesStore(
            localRepository: StubBundle.repository(bundled),
            customRepository: customRepo,
            favoritesStore: FavoritesStore(defaults: isolatedDefaults()),
            householdID: household
        )
        await store.load()
        return store
    }

    /// A fresh isolated UserDefaults suite per store so favorites never leak.
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.recipes.\(UUID().uuidString)")!
    }

    // MARK: Merge / dedup (custom wins, bundled order preserved)

    @Test func mergePrefersCustomOnSharedIdKeepingBundledSlot() {
        let bundled = [
            recipe(id: "a", name: "番茄炒蛋", category: "家常"),
            recipe(id: "b", name: "青椒肉丝", category: "川菜"),
        ]
        let custom = [
            recipe(id: "b", name: "我的青椒肉丝", category: "川菜"), // overrides b
            recipe(id: "c", name: "自创菜", category: "其他"), // appended
        ]
        let merged = RecipesStore.merge(bundled: bundled, custom: custom)
        #expect(merged.map(\.id) == ["a", "b", "c"]) // bundled order + appended custom
        #expect(merged.first { $0.id == "b" }?.name == "我的青椒肉丝") // custom won
    }

    @Test func loadMergesBundledAndCustomCustomWins() async throws {
        let store = try await makeStore(
            bundled: [recipe(id: "shared", name: "原版", category: "家常")],
            custom: [recipe(id: "shared", name: "改版", category: "家常")]
        )
        #expect(store.recipes.count == 1)
        #expect(store.recipes.first?.name == "改版")
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    // MARK: Category filter

    @Test func categoryFilterRestrictsToCategory() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "番茄炒蛋", category: "家常"),
            recipe(id: "b", name: "宫保鸡丁", category: "川菜"),
            recipe(id: "c", name: "麻婆豆腐", category: "川菜"),
        ])
        store.categoryFilter = "川菜"
        #expect(store.displayRecipes.map(\.id) == ["b", "c"])
        store.categoryFilter = nil
        #expect(store.displayRecipes.count == 3)
    }

    @Test func categoryOptionsOrderedByCountThenFirstAppearance() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "n1", category: "家常"),
            recipe(id: "b", name: "n2", category: "川菜"),
            recipe(id: "c", name: "n3", category: "川菜"),
            recipe(id: "d", name: "n4", category: "粤菜"),
        ])
        // 川菜(2) first, then 家常 / 粤菜 (1 each) by first appearance.
        #expect(store.categoryOptions == ["川菜", "家常", "粤菜"])
    }

    @Test func staleCategoryFilterTreatedAsAll() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "番茄炒蛋", category: "家常"),
        ])
        store.categoryFilter = "不存在的分类"
        #expect(store.effectiveCategory == nil)
        #expect(store.displayRecipes.count == 1) // not silently emptied
    }

    // MARK: Search (name OR ingredient, case-insensitive)

    @Test func searchMatchesRecipeName() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "番茄炒蛋", category: "家常"),
            recipe(id: "b", name: "青椒肉丝", category: "川菜"),
        ])
        store.searchQuery = " 番茄 "
        #expect(store.displayRecipes.map(\.id) == ["a"])
    }

    @Test func searchMatchesIngredientName() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "随便一道菜", category: "家常",
                   ingredients: [RecipeIngredient(name: "鸡胸肉")]),
            recipe(id: "b", name: "另一道菜", category: "家常",
                   ingredients: [RecipeIngredient(name: "土豆")]),
        ])
        store.searchQuery = "鸡胸"
        #expect(store.displayRecipes.map(\.id) == ["a"])
    }

    @Test func searchIsCaseInsensitive() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "Salmon Steak", category: "西式"),
            recipe(id: "b", name: "牛奶布丁", category: "烘焙"),
        ])
        store.searchQuery = "salmon"
        #expect(store.displayRecipes.map(\.id) == ["a"])
    }

    // MARK: Favorites-only filter

    @Test func favoritesOnlyShowsFavoritedRecipes() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "番茄炒蛋", category: "家常"),
            recipe(id: "b", name: "青椒肉丝", category: "川菜"),
        ])
        store.toggleFavorite(store.recipes.first { $0.id == "b" }!)
        store.favoritesOnly = true
        #expect(store.displayRecipes.map(\.id) == ["b"])
        #expect(store.favoriteCount == 1)
        // Toggling off restores both.
        store.favoritesOnly = false
        #expect(store.displayRecipes.count == 2)
    }

    @Test func filtersComposeCategoryAndSearchAndFavorites() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "川味鸡", category: "川菜"),
            recipe(id: "b", name: "川味鱼", category: "川菜"),
            recipe(id: "c", name: "家常鸡", category: "家常"),
        ])
        store.toggleFavorite(store.recipes.first { $0.id == "a" }!)
        store.categoryFilter = "川菜"
        store.searchQuery = "鸡"
        store.favoritesOnly = true
        #expect(store.displayRecipes.map(\.id) == ["a"]) // all three narrow to a
    }

    @Test func hasActiveQueryReflectsAnyFilter() async throws {
        let store = try await makeStore(bundled: [recipe(id: "a", name: "菜", category: "家常")])
        #expect(!store.hasActiveQuery)
        store.searchQuery = "菜"
        #expect(store.hasActiveQuery)
        store.searchQuery = ""
        store.categoryFilter = "家常"
        #expect(store.hasActiveQuery)
        store.categoryFilter = nil
        store.favoritesOnly = true
        #expect(store.hasActiveQuery)
    }

    // MARK: Source order not mutated by derivation

    @Test func derivingDisplayDoesNotReorderSource() async throws {
        let store = try await makeStore(bundled: [
            recipe(id: "a", name: "n1", category: "川菜"),
            recipe(id: "b", name: "n2", category: "家常"),
        ])
        let before = store.recipes.map(\.id)
        store.categoryFilter = "家常"
        _ = store.displayRecipes
        #expect(store.recipes.map(\.id) == before)
    }
}

/// Helper that wraps a fixed recipe set in a `LocalRecipeRepository`-shaped seam
/// by serializing to JSON and decoding through the same per-entry path the real
/// loader uses — so tests exercise the production decode, not a bypass.
private enum StubBundle {
    static func repository(_ recipes: [Recipe]) -> LocalRecipeRepository {
        let data = (try? JSONEncoder().encode(recipes)) ?? Data("[]".utf8)
        return LocalRecipeRepository(payload: data)
    }
}
