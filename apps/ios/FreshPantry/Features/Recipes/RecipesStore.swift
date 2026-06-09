import Foundation

/// Feature store for the Recipes browse slice — the same `@Observable @MainActor`
/// template the Inventory / Shopping stores established.
///
/// Merges the read-only bundled HowToCook corpus (`LocalRecipeRepository`) with
/// the user's custom recipes (`CustomRecipeRepository`), de-duping by `id` with
/// **custom winning** (a user edit of a bundled recipe overrides the bundled
/// copy — mirrors `recommendedRecipesProvider`'s id-dedup merge). Holds the
/// category / search / favorites-only filter state and exposes the derived
/// `displayRecipes`. Favorite state is delegated to the shared `FavoritesStore`.
/// Views never decode the bundle or touch SwiftData directly.
@Observable
@MainActor
final class RecipesStore {
    /// Category filter. `nil` = 全部 (all categories).
    var categoryFilter: String?
    var searchQuery: String = ""
    var favoritesOnly: Bool = false

    private let localRepository: LocalRecipeRepository
    private let customRepository: CustomRecipeRepository
    private let favoritesStore: FavoritesStore
    private let householdID: String

    /// Merged, id-deduped recipes (bundled order first, custom appended; custom
    /// overrides a shared id in place). The parity-critical source order is never
    /// mutated by display concerns.
    private(set) var recipes: [Recipe] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    init(
        localRepository: LocalRecipeRepository,
        customRepository: CustomRecipeRepository,
        favoritesStore: FavoritesStore,
        householdID: String
    ) {
        self.localRepository = localRepository
        self.customRepository = customRepository
        self.favoritesStore = favoritesStore
        self.householdID = householdID
    }

    // MARK: Loading

    /// Loads bundled + custom recipes and merges them (custom wins on id).
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let bundled = await localRepository.loadAll()
        let custom = (try? await customRepository.loadAllFor(householdID)) ?? []
        recipes = Self.merge(bundled: bundled, custom: custom)
    }

    /// Bundled first, then custom; a custom recipe with the same id REPLACES the
    /// bundled one in its original slot (custom wins), and a brand-new custom
    /// recipe is appended. Keeps bundled ordering otherwise.
    static func merge(bundled: [Recipe], custom: [Recipe]) -> [Recipe] {
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var result: [Recipe] = []
        var seen = Set<String>()
        for recipe in bundled {
            seen.insert(recipe.id)
            result.append(customByID[recipe.id] ?? recipe)
        }
        for recipe in custom where !seen.contains(recipe.id) {
            seen.insert(recipe.id)
            result.append(recipe)
        }
        return result
    }

    // MARK: Favorites (delegated to the shared store)

    func isFavorite(_ recipe: Recipe) -> Bool {
        favoritesStore.isFavorite(recipe.id)
    }

    @discardableResult
    func toggleFavorite(_ recipe: Recipe) -> Bool {
        favoritesStore.toggle(recipe.id)
    }

    // MARK: Derived view data

    /// The list the view renders: category filter → name/ingredient search →
    /// favorites-only filter. A stale category filter (not present in the corpus)
    /// is treated as 全部 so it never silently empties the list (blueprint
    /// invariant 7).
    var displayRecipes: [Recipe] {
        let activeCategory = effectiveCategory
        return recipes
            .filter { Self.matchesCategory($0, activeCategory) }
            .filter { Self.matchesSearch($0, query: searchQuery) }
            .filter(matchesFavorites)
    }

    /// Distinct non-blank categories ordered by count desc, ties by first
    /// appearance (ports `recipeCategoryOptions`). Drives the filter chips.
    var categoryOptions: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for recipe in recipes {
            let category = recipe.category.trimmed
            guard !category.isEmpty else { continue }
            if counts[category] == nil { order.append(category) }
            counts[category, default: 0] += 1
        }
        return order.sorted { lhs, rhs in
            let lc = counts[lhs] ?? 0
            let rc = counts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    /// The category filter actually applied: the selected one if it's still a
    /// present option, else `nil` (全部).
    var effectiveCategory: String? {
        guard let categoryFilter, categoryOptions.contains(categoryFilter) else { return nil }
        return categoryFilter
    }

    /// True when any filter/search is narrowing the list (drives empty-state copy).
    var hasActiveQuery: Bool {
        !searchQuery.trimmed.isEmpty || effectiveCategory != nil || favoritesOnly
    }

    var favoriteCount: Int {
        recipes.filter { favoritesStore.isFavorite($0.id) }.count
    }

    // MARK: Filtering internals

    private static func matchesCategory(_ recipe: Recipe, _ category: String?) -> Bool {
        guard let category else { return true }
        return recipe.category.trimmed == category.trimmed
    }

    /// Case-insensitive contains on the recipe name OR any ingredient name
    /// (ports the RecipesScreen search predicate).
    private static func matchesSearch(_ recipe: Recipe, query: String) -> Bool {
        let needle = query.trimmed.lowercased()
        if needle.isEmpty { return true }
        if recipe.name.lowercased().contains(needle) { return true }
        return recipe.ingredients.contains { $0.name.lowercased().contains(needle) }
    }

    private func matchesFavorites(_ recipe: Recipe) -> Bool {
        guard favoritesOnly else { return true }
        return favoritesStore.isFavorite(recipe.id)
    }
}
