import Foundation

/// 临期投影。`daysRemaining` 按 widget 渲染时刻重算(每天跨午夜刷新后变化)。
public struct WidgetExpiringSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let name: String
        public let daysRemaining: Int?  // nil = 无到期日
        public init(name: String, daysRemaining: Int?) {
            self.name = name
            self.daysRemaining = daysRemaining
        }
    }
    public let expiredCount: Int
    public let urgentCount: Int
    public let soonCount: Int
    public let items: [Item]

    public init(expiredCount: Int, urgentCount: Int, soonCount: Int, items: [Item]) {
        self.expiredCount = expiredCount
        self.urgentCount = urgentCount
        self.soonCount = soonCount
        self.items = items
    }

    public var needsAttentionCount: Int { expiredCount + urgentCount + soonCount }
    public static let empty = WidgetExpiringSnapshot(expiredCount: 0, urgentCount: 0, soonCount: 0, items: [])
}

/// 今日膳食投影(只含今天的条目)。
public struct WidgetMealPlanSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let title: String
        public let done: Bool
        public let mealType: String?
        public init(title: String, done: Bool, mealType: String?) {
            self.title = title
            self.done = done
            self.mealType = mealType
        }
    }
    public let items: [Item]
    public init(items: [Item]) { self.items = items }
    public static let empty = WidgetMealPlanSnapshot(items: [])
}

/// 购物投影。`items` 已「未勾选优先」并截断;每行带 id 供交互按钮回写。
public struct WidgetShoppingSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let isChecked: Bool
        public init(id: String, name: String, isChecked: Bool) {
            self.id = id
            self.name = name
            self.isChecked = isChecked
        }
    }
    public let uncheckedCount: Int
    public let items: [Item]
    public init(uncheckedCount: Int, items: [Item]) {
        self.uncheckedCount = uncheckedCount
        self.items = items
    }
    public static let empty = WidgetShoppingSnapshot(uncheckedCount: 0, items: [])
}

/// 减废投影(复用 Domain 的 FoodLogStatistics 口径)。
public struct WidgetWasteSnapshot: Codable, Equatable, Sendable {
    public let useUpPercent: Int
    public let rescuedCount: Int
    public let consumedCount: Int
    public let wastedCount: Int
    public let isEmpty: Bool
    public init(useUpPercent: Int, rescuedCount: Int, consumedCount: Int, wastedCount: Int, isEmpty: Bool) {
        self.useUpPercent = useUpPercent
        self.rescuedCount = rescuedCount
        self.consumedCount = consumedCount
        self.wastedCount = wastedCount
        self.isEmpty = isEmpty
    }
    public static let empty = WidgetWasteSnapshot(useUpPercent: 0, rescuedCount: 0, consumedCount: 0, wastedCount: 0, isEmpty: true)
}

/// 四类内容的合集快照,一次读取填满(Provider 只读一次容器)。
public struct WidgetSnapshotBundle: Codable, Equatable, Sendable {
    public var expiring: WidgetExpiringSnapshot = .empty
    public var mealPlan: WidgetMealPlanSnapshot = .empty
    public var shopping: WidgetShoppingSnapshot = .empty
    public var waste: WidgetWasteSnapshot = .empty
    public init(
        expiring: WidgetExpiringSnapshot = .empty,
        mealPlan: WidgetMealPlanSnapshot = .empty,
        shopping: WidgetShoppingSnapshot = .empty,
        waste: WidgetWasteSnapshot = .empty
    ) {
        self.expiring = expiring
        self.mealPlan = mealPlan
        self.shopping = shopping
        self.waste = waste
    }
    public static let empty = WidgetSnapshotBundle()
}
