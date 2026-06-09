import Foundation
import Testing
@testable import FreshPantry

/// Tests for the bundled HowToCook corpus loader: the shipped asset decodes to a
/// non-empty `[Recipe]`, per-entry resilience skips malformed rows, and a
/// non-array payload yields an empty list (never throws).
struct LocalRecipeRepositoryTests {
    // MARK: Bundled asset

    @Test func bundledAssetDecodesToNonEmptyRecipes() async throws {
        let repo = LocalRecipeRepository()
        let recipes = await repo.loadAll()
        #expect(!recipes.isEmpty)
        // Every decoded recipe has the id+name the merge/favorites paths require.
        #expect(recipes.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }

    @Test func loadIsCachedAcrossCalls() async throws {
        let repo = LocalRecipeRepository()
        let first = await repo.loadAll()
        let second = await repo.loadAll()
        #expect(first.count == second.count)
        #expect(first.count > 0)
    }

    // MARK: Per-entry resilience

    @Test func malformedEntryIsSkippedRestPreserved() {
        // A valid recipe, a non-object entry, and a second valid recipe.
        let json = """
        [
          {"id":"a","name":"番茄炒蛋","category":"家常","difficulty":1,"cookingMinutes":15,
           "description":"","ingredients":[],"steps":[]},
          12345,
          {"id":"b","name":"青椒肉丝","category":"川菜","difficulty":2,"cookingMinutes":20,
           "description":"","ingredients":[],"steps":[]}
        ]
        """
        let recipes = LocalRecipeRepository.decode(data: Data(json.utf8))
        #expect(recipes.map(\.id) == ["a", "b"]) // bad middle entry skipped
    }

    @Test func nonArrayPayloadYieldsEmpty() {
        let recipes = LocalRecipeRepository.decode(data: Data(#"{"not":"an array"}"#.utf8))
        #expect(recipes.isEmpty)
    }

    @Test func injectedPayloadOverridesBundle() async {
        let json = #"[{"id":"x","name":"注入","category":"家常","difficulty":1,"cookingMinutes":10,"description":"","ingredients":[],"steps":[]}]"#
        let repo = LocalRecipeRepository(payload: Data(json.utf8))
        let recipes = await repo.loadAll()
        #expect(recipes.map(\.id) == ["x"])
    }
}
