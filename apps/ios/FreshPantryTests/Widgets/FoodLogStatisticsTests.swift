import Foundation
import Testing
@testable import FreshPantry

struct FoodLogStatisticsTests {
    private func entry(_ outcome: FoodLogOutcome, wasExpiring: Bool = false) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID().uuidString,
            name: "x",
            category: FoodCategories.other,
            outcome: outcome,
            loggedAt: Date(timeIntervalSince1970: 0),
            wasExpiring: wasExpiring,
            remoteVersion: 0
        )
    }

    @Test func talliesConsumedWastedRescuedSaved() {
        let stats = FoodLogStatistics.computeStats([
            entry(.consumed),
            entry(.consumed, wasExpiring: true),
            entry(.wasted),
            entry(.donated),
            entry(.composted),
        ])
        #expect(stats.consumed == 2)
        #expect(stats.wasted == 1)
        #expect(stats.rescued == 1)
        #expect(stats.saved == 2)
        #expect(stats.total == 3)        // consumed + wasted(saved/rescued 不在分母)
        #expect(stats.useUpPercent == 67) // 2/3 = 66.7 → 67
    }

    @Test func emptyIsZero() {
        let stats = FoodLogStatistics.computeStats([])
        #expect(stats.isEmpty)
        #expect(stats.useUpPercent == 0)
    }

    /// 兼容壳:旧 call site / 测试仍可经 WasteInsightsStore 调用,结果一致。
    /// `WasteInsightsStore` 是 `@MainActor`,其静态转发壳随之 main-actor 隔离,
    /// 故此用例须在 main actor 上调用(与既有 WasteInsightsStoreTests 一致)。
    @MainActor
    @Test func wasteStoreWrapperMatches() {
        let entries = [entry(.consumed), entry(.wasted)]
        #expect(WasteInsightsStore.computeStats(entries) == FoodLogStatistics.computeStats(entries))
    }
}
