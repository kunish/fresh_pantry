import Foundation
import Testing
@testable import FreshPantry

/// Guards recipe-cover resolution: the 174 HowToCook covers must stay bundled (a
/// dropped `RecipeImages/` folder reference silently regresses every cover to the
/// category glyph) and `RecipeImageStore` must route each source shape correctly.
@MainActor
struct RecipeImageTests {
    /// A real bundled cover path from `howtocook.json`. If the folder reference is
    /// lost, this resolves to nil and the test fails — exactly the regression we want
    /// to catch before it ships.
    private let bundledAsset = "assets/recipes/images/howtocook_aquatic_小龙虾_小龙虾.jpg"

    @Test func bundledAssetResolvesToImage() {
        #expect(RecipeImageStore.localImage(for: bundledAsset) != nil)
    }

    @Test func missingBundledAssetIsNil() {
        #expect(RecipeImageStore.localImage(for: "assets/recipes/images/__does_not_exist__.jpg") == nil)
    }

    @Test func remoteSourceIsNotResolvedLocally() {
        // Remote URLs are AsyncImage's job — the local store must decline them so the
        // view falls through to its `AsyncImage` branch.
        #expect(RecipeImageStore.localImage(for: "https://example.com/cover.jpg") == nil)
        #expect(RecipeImageStore.localImage(for: "http://example.com/cover.jpg") == nil)
    }

    @Test func inlineDataImageResolves() {
        // 1×1 PNG as a data URI (an AI / pasted cover shape).
        let onePxPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
        #expect(RecipeImageStore.localImage(for: onePxPNG) != nil)
    }

    @Test func malformedInlineDataIsNil() {
        #expect(RecipeImageStore.localImage(for: "data:image/png;base64,@@notbase64@@") == nil)
    }
}
