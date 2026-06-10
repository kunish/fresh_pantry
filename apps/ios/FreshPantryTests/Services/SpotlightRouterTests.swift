import Testing
@testable import FreshPantry

/// Semantics of the Spotlight deep-link router: capture parses the tapped
/// result's identifier (malformed → no-op), consume is one-shot, clear
/// discards without reading. Mirrors `NotificationTapRouterTests`.
@MainActor
struct SpotlightRouterTests {
    @Test func startsWithNoPendingItem() {
        let router = SpotlightRouter()
        #expect(router.pendingItem == nil)
    }

    @Test func captureParsesIngredientIdentifier() {
        let router = SpotlightRouter()
        router.capture(identifier: "ingredient:abc")
        #expect(router.pendingItem == .ingredient("abc"))
    }

    @Test func captureParsesRecipeIdentifier() {
        let router = SpotlightRouter()
        router.capture(identifier: "recipe:r-7")
        #expect(router.pendingItem == .recipe("r-7"))
    }

    @Test func captureIgnoresMalformedIdentifier() {
        let router = SpotlightRouter()
        router.capture(identifier: "garbage")
        #expect(router.pendingItem == nil)
        // …and a malformed capture must not clobber a pending valid one.
        router.capture(identifier: "ingredient:abc")
        router.capture(identifier: "shopping:zzz")
        #expect(router.pendingItem == .ingredient("abc"))
    }

    @Test func captureOverwritesPreviousPendingItem() {
        let router = SpotlightRouter()
        router.capture(identifier: "ingredient:a")
        router.capture(identifier: "recipe:b")
        #expect(router.pendingItem == .recipe("b"))
    }

    @Test func consumeReturnsItemOnceThenNil() {
        let router = SpotlightRouter()
        router.capture(identifier: "recipe:b")
        #expect(router.consume() == .recipe("b"))
        #expect(router.pendingItem == nil)
        #expect(router.consume() == nil)
    }

    @Test func clearDiscardsPendingItem() {
        let router = SpotlightRouter()
        router.capture(identifier: "ingredient:a")
        router.clear()
        #expect(router.pendingItem == nil)
    }
}
