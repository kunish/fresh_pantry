import Foundation
import Testing
@testable import FreshPantry

/// The single urgency ordering (Domain/Rules/FreshnessSort) shared by the
/// Inventory list, the Dashboard 临期 preview, and the Expiring board.
struct FreshnessSortTests {
    private func item(_ id: String, _ state: FreshnessState, daysFromNow: Int? = nil) -> Ingredient {
        let expiry = daysFromNow.map { Date(timeIntervalSince1970: 1_000_000 + Double($0) * 86_400) }
        return Ingredient(
            id: id, name: id, quantity: "1", unit: "份",
            imageUrl: "", freshnessPercent: 1, state: state, expiryDate: expiry
        )
    }

    @Test func mostSevereStateFirst() {
        let sorted = FreshnessSort.byUrgency([
            item("fresh", .fresh),
            item("soon", .expiringSoon),
            item("expired", .expired),
            item("urgent", .urgent),
        ])
        #expect(sorted.map(\.id) == ["expired", "urgent", "soon", "fresh"])
    }

    @Test func soonestExpiryFirstWithinTier() {
        let sorted = FreshnessSort.byUrgency([
            item("late", .urgent, daysFromNow: 5),
            item("soon", .urgent, daysFromNow: 1),
            item("mid", .urgent, daysFromNow: 3),
        ])
        #expect(sorted.map(\.id) == ["soon", "mid", "late"])
    }

    @Test func nilExpirySinksLastWithinTier() {
        let sorted = FreshnessSort.byUrgency([
            item("noDate", .urgent, daysFromNow: nil),
            item("dated", .urgent, daysFromNow: 2),
        ])
        #expect(sorted.map(\.id) == ["dated", "noDate"])
    }

    @Test func stableForEqualKeys() {
        // Same tier, both nil expiry → original order preserved (stable by index).
        let sorted = FreshnessSort.byUrgency([
            item("a", .fresh),
            item("b", .fresh),
            item("c", .fresh),
        ])
        #expect(sorted.map(\.id) == ["a", "b", "c"])
    }
}
