import Foundation
import Testing
@testable import FreshPantry

/// Tests for the UserDefaults-backed favorites KV store: toggle semantics,
/// JSON-string-array persistence round-trip via an injected suite, defensive
/// decode, and the blank-id guard. Establishes the reusable settings-store
/// pattern.
@MainActor
struct FavoritesStoreTests {
    /// A fresh isolated suite per test so persisted blobs never leak between runs.
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.favorites.\(UUID().uuidString)")!
    }

    // MARK: Toggle

    @Test func toggleAddsThenRemoves() {
        let store = FavoritesStore(defaults: suite())
        #expect(!store.isFavorite("r1"))
        #expect(store.toggle("r1") == true)
        #expect(store.isFavorite("r1"))
        #expect(store.toggle("r1") == false)
        #expect(!store.isFavorite("r1"))
    }

    @Test func toggleIgnoresBlankId() {
        let store = FavoritesStore(defaults: suite())
        #expect(store.toggle("   ") == false)
        #expect(store.favoriteIDs.isEmpty)
    }

    // MARK: Persistence round-trip

    @Test func favoritesPersistAcrossInstancesViaSharedSuite() {
        let defaults = suite()
        let first = FavoritesStore(defaults: defaults)
        first.toggle("a")
        first.toggle("b")

        // A new store over the same suite reads the persisted blob.
        let second = FavoritesStore(defaults: defaults)
        #expect(second.isFavorite("a"))
        #expect(second.isFavorite("b"))
        #expect(second.favoriteIDs == ["a", "b"])
    }

    @Test func persistedBlobIsAJsonStringArray() {
        let defaults = suite()
        let store = FavoritesStore(defaults: defaults)
        store.toggle("b")
        store.toggle("a")
        let raw = defaults.string(forKey: FavoritesStore.storageKey)
        #expect(raw != nil)
        // Sorted JSON array → diff-stable; decodes back to the same set.
        #expect(raw == #"["a","b"]"#)
        #expect(FavoritesStore.decode(raw) == ["a", "b"])
    }

    @Test func removingLastFavoritePersistsEmptyArray() {
        let defaults = suite()
        let store = FavoritesStore(defaults: defaults)
        store.toggle("only")
        store.toggle("only")
        let reloaded = FavoritesStore(defaults: defaults)
        #expect(reloaded.favoriteIDs.isEmpty)
    }

    // MARK: Defensive decode

    @Test func decodeHandlesNilEmptyAndMalformed() {
        #expect(FavoritesStore.decode(nil).isEmpty)
        #expect(FavoritesStore.decode("").isEmpty)
        #expect(FavoritesStore.decode("not json").isEmpty)
        #expect(FavoritesStore.decode(#"{"k":"v"}"#).isEmpty) // object, not array
        // Non-string / blank elements are dropped; valid ids kept.
        #expect(FavoritesStore.decode(#"["a", 1, "", "b"]"#) == ["a", "b"])
    }
}
