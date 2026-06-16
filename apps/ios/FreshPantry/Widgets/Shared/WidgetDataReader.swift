import Foundation
import SwiftData
import WidgetKit

/// 从共享 SwiftData 容器派生小组件展示数据。复用既有 `@ModelActor` repo 加载,
/// 派生口径对齐 app(`ExpiryCalculator` 临期分级,`FoodLogStatistics` 减废)。
/// 仅依赖 Domain 层 + 共享 repo,不触碰 Features/UI/网络层(本类型会编进 widget)。
/// 所有方法纯读不写。
struct WidgetDataReader {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// **Provider 实际走这条**:只算当前 family + 选中内容真正要展示的那一类快照,
    /// 其余留 `.empty`。widget 扩展进程有约 30MB 硬内存上限,一次性算四类(各开一个
    /// `@ModelActor` + 全量 fetch/decode)极易超限被系统 jetsam 杀掉 → 永远停在占位
    /// 渲染不出内容;故按需只取一类,把峰值内存/CPU 压到最小。
    /// circular / inline 配件永远只显示临期(与所选内容无关)。
    func bundle(for content: WidgetContentChoice, family: WidgetFamily, householdID: String, now: Date) async -> WidgetSnapshotBundle {
        switch family {
        case .accessoryCircular, .accessoryInline:
            return WidgetSnapshotBundle(expiring: await expiringSnapshot(householdID: householdID, now: now, limit: 8))
        default:
            switch content {
            case .expiring:
                return WidgetSnapshotBundle(expiring: await expiringSnapshot(householdID: householdID, now: now, limit: 8))
            case .mealPlan:
                return WidgetSnapshotBundle(mealPlan: await mealPlanSnapshot(householdID: householdID, now: now))
            case .shopping:
                return WidgetSnapshotBundle(shopping: await shoppingSnapshot(householdID: householdID, limit: 8))
            case .waste:
                return WidgetSnapshotBundle(waste: await wasteSnapshot(householdID: householdID, now: now))
            }
        }
    }

    /// 一次读满四类内容。仅供测试与非内存敏感场景;Provider 改走 `bundle(for:family:…)`
    /// 选择性加载(见其文档:widget 进程内存预算)。
    func snapshotBundle(householdID: String, now: Date) async -> WidgetSnapshotBundle {
        async let expiring = expiringSnapshot(householdID: householdID, now: now, limit: 8)
        async let mealPlan = mealPlanSnapshot(householdID: householdID, now: now)
        async let shopping = shoppingSnapshot(householdID: householdID, limit: 8)
        async let waste = wasteSnapshot(householdID: householdID, now: now)
        return await WidgetSnapshotBundle(
            expiring: expiring, mealPlan: mealPlan, shopping: shopping, waste: waste
        )
    }

    // MARK: 临期

    func expiringSnapshot(householdID: String, now: Date, limit: Int) async -> WidgetExpiringSnapshot {
        let repo = InventoryRepository(modelContainer: container)
        guard let inventory = try? await repo.loadAllFor(householdID) else { return .empty }

        struct Tagged { let ingredient: Ingredient; let state: FreshnessState; let days: Int? }
        let tagged: [Tagged] = inventory.map { ing in
            let state = ExpiryCalculator.freshnessStateForExpiry(
                freshness: ing.freshnessPercent, expiryDate: ing.expiryDate, now: now
            )
            let days = ing.expiryDate.map { ExpiryCalculator.daysUntilExpiry($0, now: now) }
            return Tagged(ingredient: ing, state: state, days: days)
        }
        // 非新鲜 = 非 .fresh。注意:这里按渲染时刻 now 用 ExpiryCalculator 重算 tier
        // (而非读 ingredient.state 的存量值)——widget 每日跨午夜刷新需让剩余天数与
        // tier 随当天重算,即便 app 当天未运行;故刻意不复用 DashboardStore 的存量 state。
        let nonFresh = tagged.filter { $0.state != .fresh }

        // 排序:严重度(expired→urgent→soon),再最快到期优先(nil 到期日最后),稳定。
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon, .fresh]
        func rank(_ s: FreshnessState) -> Int { order.firstIndex(of: s) ?? order.count }
        let sorted = nonFresh.enumerated().sorted { lhs, rhs in
            let lr = rank(lhs.element.state), rr = rank(rhs.element.state)
            if lr != rr { return lr < rr }
            switch (lhs.element.days, rhs.element.days) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)

        func count(_ s: FreshnessState) -> Int { nonFresh.lazy.filter { $0.state == s }.count }
        let items = sorted.prefix(limit).map {
            WidgetExpiringSnapshot.Item(name: $0.ingredient.name, daysRemaining: $0.days, state: $0.state)
        }
        return WidgetExpiringSnapshot(
            expiredCount: count(.expired),
            urgentCount: count(.urgent),
            soonCount: count(.expiringSoon),
            items: Array(items)
        )
    }

    // MARK: 今日膳食

    func mealPlanSnapshot(householdID: String, now: Date) async -> WidgetMealPlanSnapshot {
        let repo = MealPlanRepository(modelContainer: container)
        guard let entries = try? await repo.loadAllFor(householdID) else { return .empty }
        let cal = Calendar.current
        let todays = entries.filter { cal.isDate($0.date, inSameDayAs: now) }
        let items = todays.map { entry in
            // 复用模型的 displayTitle(与 MealPlanView 同一真源),避免 widget 与 app 显示不一致。
            WidgetMealPlanSnapshot.Item(title: entry.displayTitle, done: entry.done, mealType: entry.mealType)
        }
        return WidgetMealPlanSnapshot(items: items)
    }

    // MARK: 购物

    func shoppingSnapshot(householdID: String, limit: Int) async -> WidgetShoppingSnapshot {
        let repo = ShoppingRepository(modelContainer: container)
        guard let all = try? await repo.loadAllFor(householdID) else { return .empty }
        let unchecked = all.lazy.filter { !$0.isChecked }.count
        // 未勾选优先,稳定保持源序。
        let sorted = all.enumerated().sorted { lhs, rhs in
            if lhs.element.isChecked != rhs.element.isChecked { return !lhs.element.isChecked }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let items = sorted.prefix(limit).map {
            WidgetShoppingSnapshot.Item(id: $0.id, name: $0.name, isChecked: $0.isChecked)
        }
        return WidgetShoppingSnapshot(uncheckedCount: unchecked, items: Array(items))
    }

    // MARK: 减废

    func wasteSnapshot(householdID: String, now: Date) async -> WidgetWasteSnapshot {
        let repo = FoodLogRepository(modelContainer: container)
        // 窗口 cutoff 用 Domain 的日历感知 helper(WasteInsightsStore 与本 reader
        // 共用,DST 安全;WasteInsightsStore 在 Features/ 未共享进 widget)。
        let sinceMs = FoodLogStatistics.recentWindowStartMillis(now: now)
        guard let entries = try? await repo.loadRecentFor(householdID, sinceMs: sinceMs) else { return .empty }
        let stats = FoodLogStatistics.computeStats(entries)
        return WidgetWasteSnapshot(
            useUpPercent: stats.useUpPercent,
            rescuedCount: stats.rescued,
            consumedCount: stats.consumed,
            wastedCount: stats.wasted,
            isEmpty: stats.isEmpty
        )
    }
}
