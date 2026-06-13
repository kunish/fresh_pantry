import Foundation
import Testing
@testable import FreshPantry

/// Tests for the offline-first household cache: the snapshot round-trip and the
/// identity guard that keeps one signed-in user's households from ever seeding
/// into another's session (the no-flash seed in `HouseholdSessionStore.init`).
struct HouseholdCacheTests {
    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("household-cache-\(UUID().uuidString).json")
    }

    private func snapshot(email: String) -> HouseholdCache.Snapshot {
        HouseholdCache.Snapshot(
            email: email,
            households: [Household(id: "h1", name: "我的家", ownerId: "u1")],
            selectedHouseholdId: "h1",
            members: [
                HouseholdMember(householdId: "h1", userId: "u1", role: "owner", email: email),
                HouseholdMember(householdId: "h1", userId: "u2", role: "member", email: "bob@x.com"),
            ]
        )
    }

    @Test func writeThenReadForSameIdentityRoundTrips() {
        let cache = HouseholdCache(fileURL: tempCacheURL())
        cache.write(snapshot(email: "alice@x.com"))

        let read = cache.read(for: "alice@x.com")
        #expect(read?.households == [Household(id: "h1", name: "我的家", ownerId: "u1")])
        #expect(read?.selectedHouseholdId == "h1")
        #expect(read?.members.count == 2)
        #expect(read?.members.first?.role == "owner")
    }

    @Test func readForDifferentIdentityReturnsNil() {
        let cache = HouseholdCache(fileURL: tempCacheURL())
        cache.write(snapshot(email: "alice@x.com"))
        // The identity guard: a different signed-in user must NOT see alice's households.
        #expect(cache.read(for: "mallory@x.com") == nil)
    }

    @Test func emailMatchIsCaseInsensitiveAndTrimmed() {
        let cache = HouseholdCache(fileURL: tempCacheURL())
        cache.write(snapshot(email: "Alice@X.com"))
        #expect(cache.read(for: "  alice@x.COM ") != nil)
    }

    @Test func readForSignedOutReturnsNil() {
        let cache = HouseholdCache(fileURL: tempCacheURL())
        cache.write(snapshot(email: "alice@x.com"))
        #expect(cache.read(for: nil) == nil)
        #expect(cache.read(for: "") == nil)
    }

    @Test func readWithNoCacheFileReturnsNil() {
        let cache = HouseholdCache(fileURL: tempCacheURL())
        #expect(cache.read(for: "alice@x.com") == nil)
    }
}
