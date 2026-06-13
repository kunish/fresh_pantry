import Foundation
import Testing
@testable import FreshPantry

/// Guards recipe-cover resolution. Covers now ship from Supabase Storage (the
/// `RecipeImages/` bundle was dropped to save ~111MB), so a remote `http(s)` URL
/// must be DECLINED by the local store and handed to `CachedRemoteImage`
/// (disk-cached); `RecipeImageStore` still routes `data:`/`file://`/`assets://`
/// shapes for inline + custom-recipe covers.
@MainActor
struct RecipeImageTests {
    @Test func missingBundledAssetIsNil() {
        #expect(RecipeImageStore.localImage(for: "assets/recipes/images/__does_not_exist__.jpg") == nil)
    }

    @Test func remoteSourceIsNotResolvedLocally() {
        // Remote URLs are `CachedRemoteImage`'s job — the local store must decline
        // them so the view falls through to its disk-cached remote branch.
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
