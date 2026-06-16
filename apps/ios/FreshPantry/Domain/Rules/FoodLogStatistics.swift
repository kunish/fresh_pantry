import Foundation

/// 一个时间窗内的食材去向统计。全是「件数」,绝不汇总数量(数量是自由文本,
/// 故意不求和)。`useUpRate` 是头条指标;`/0` 守卫为 0(尚无去向)。
///
/// 从 `WasteInsightsStore` 抽出,使小组件可在不拖入 `SyncWriter`(网络层)的
/// 前提下复用同一套口径。
struct FoodLogStats: Equatable, Sendable {
    var consumed: Int
    var wasted: Int
    /// Consumed AND already past fresh — "抢救临期" credit.
    var rescued: Int
    /// Donated + composted — positive去向, NOT counted as waste.
    var saved: Int = 0

    static let empty = FoodLogStats(consumed: 0, wasted: 0, rescued: 0, saved: 0)

    /// consumed + wasted(rescued 是 consumed 的子集;saved 是另一种正向去向,
    /// 不进用掉率分母)。
    var total: Int { consumed + wasted }

    /// consumed / (consumed + wasted),无去向时为 0(守卫 /0)。
    var useUpRate: Double { total == 0 ? 0 : Double(consumed) / Double(total) }

    /// 0...100 整数百分比(如 85 → "85% 用掉率")。
    var useUpPercent: Int { Int((useUpRate * 100).rounded()) }

    var isEmpty: Bool { total == 0 }
}

/// 纯聚合(无 SwiftData,可单测)。
enum FoodLogStatistics {
    /// Tallies consumed / wasted / rescued / saved over `entries`. `rescued`
    /// counts a consumed entry whose batch was already expiring (`wasExpiring`).
    static func computeStats(_ entries: [FoodLogEntry]) -> FoodLogStats {
        var consumed = 0
        var wasted = 0
        var rescued = 0
        var saved = 0
        for entry in entries {
            if entry.isConsumed {
                consumed += 1
                if entry.wasExpiring { rescued += 1 }
            } else if entry.outcome.isSaved {
                // 捐了/堆肥 = 非浪费正向去向,绝不计入 wasted。
                saved += 1
            } else {
                wasted += 1
            }
        }
        return FoodLogStats(consumed: consumed, wasted: wasted, rescued: rescued, saved: saved)
    }
}
