import Foundation
import SwiftData

/// 从共享 SwiftData 容器派生小组件展示数据。复用既有 `@ModelActor` repo 加载,
/// 派生口径对齐 app(`ExpiryCalculator` 临期分级,`FoodLogStatistics` 减废)。
/// 仅依赖 Domain 层 + 共享 repo,不触碰 Features/UI/网络层(本类型会编进 widget)。
/// 所有方法纯读不写。
struct WidgetDataReader {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// 一次读满四类内容(Provider 调用,只开一次容器)。
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
        // 非新鲜 = 非 .fresh(等价 DashboardStore.isNonFresh,但 DashboardStore 在
        // Features/ 未共享进 widget,故就地判定——reader 是自包含的镜像派生)。
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
        let items = todays.map { entry -> WidgetMealPlanSnapshot.Item in
            let title = (entry.title?.isEmpty == false) ? entry.title! : entry.recipeName
            return WidgetMealPlanSnapshot.Item(title: title, done: entry.done, mealType: entry.mealType)
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
        // 窗口常量在 Domain 的 FoodLogStatistics(WasteInsightsStore 在 Features/
        // 未共享进 widget;两者经 FoodLogStatistics.recentWindowDays 单一真源)。
        let sinceMs = Int(now.addingTimeInterval(-Double(FoodLogStatistics.recentWindowDays) * 86_400).timeIntervalSince1970 * 1000)
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
