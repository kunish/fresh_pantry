import Foundation
import Testing
@testable import FreshPantry

/// #15 去向口径: donated/composted are POSITIVE — counted as `saved`, never as
/// waste, across the waste stats.
@MainActor
struct WasteSavedOutcomeTests {
    private func entry(_ outcome: FoodLogOutcome, _ category: String = "果蔬生鲜", expiring: Bool = false) -> FoodLogEntry {
        FoodLogEntry(
            id: FoodLogEntry.newId(), name: "x", category: category,
            outcome: outcome, loggedAt: Date(timeIntervalSince1970: 1), wasExpiring: expiring
        )
    }

    @Test func isSavedFlag() {
        #expect(FoodLogOutcome.donated.isSaved)
        #expect(FoodLogOutcome.composted.isSaved)
        #expect(!FoodLogOutcome.consumed.isSaved)
        #expect(!FoodLogOutcome.wasted.isSaved)
    }

    @Test func fromNameDecodesNewCases() {
        #expect(FoodLogOutcome.fromName("donated") == .donated)
        #expect(FoodLogOutcome.fromName("composted") == .composted)
        #expect(FoodLogOutcome.fromName("garbage") == .consumed) // unknown → conservative
    }

    @Test func computeStatsCountsSavedNotWasted() {
        let stats = WasteInsightsStore.computeStats([
            entry(.consumed), entry(.wasted), entry(.donated), entry(.composted),
        ])
        #expect(stats.consumed == 1)
        #expect(stats.wasted == 1) // donated/composted NOT here
        #expect(stats.saved == 2)
    }

    @Test func useUpRateExcludesSavedFromDenominator() {
        // 1 consumed, 1 wasted, 2 saved → total = consumed+wasted = 2 → 50%.
        let stats = WasteInsightsStore.computeStats([
            entry(.consumed), entry(.wasted), entry(.donated), entry(.composted),
        ])
        #expect(stats.total == 2)
        #expect(stats.useUpPercent == 50)
    }

    @Test func mostWastedExcludesSaved() {
        let ranked = WasteInsightsStore.computeMostWasted([
            entry(.wasted, "肉类海鲜"), entry(.donated, "肉类海鲜"), entry(.composted, "果蔬生鲜"),
        ])
        #expect(ranked.count == 1)
        #expect(ranked.first?.category == "肉类海鲜")
        #expect(ranked.first?.count == 1) // donated/composted not counted
    }

    @Test func categoryBreakdownExcludesSavedFromWasted() {
        let breakdown = WasteInsightsStore.computeCategoryBreakdown([
            entry(.consumed, "果蔬生鲜"), entry(.donated, "果蔬生鲜"), entry(.wasted, "果蔬生鲜"),
        ])
        let produce = breakdown.first { $0.category == "果蔬生鲜" }
        #expect(produce?.consumed == 1)
        #expect(produce?.wasted == 1) // the donated one is excluded
    }

    @Test func donatedOutcomeSurvivesCodableRoundTrip() throws {
        let e = entry(.donated)
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(FoodLogEntry.self, from: data)
        #expect(decoded.outcome == .donated)
    }
}
