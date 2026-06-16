import SwiftUI
import WidgetKit

// 4 个独立固定 widget(零配置依赖,真机稳定)+ 1 个可配置 widget(补充,真机可配置性待验证)。
// 每个都支持系统尺寸 + 锁屏配件(circular/rectangular/inline),配件按各自内容类别渲染。

private let allFamilies: [WidgetFamily] = [
    .systemSmall, .systemMedium, .systemLarge,
    .accessoryCircular, .accessoryRectangular, .accessoryInline,
]

struct ExpiringWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryExpiring", provider: SnapshotProvider(content: .expiring)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("临期食材")
        .description("临期 / 过期食材一览")
        .supportedFamilies(allFamilies)
    }
}

struct MealPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryMealPlan", provider: SnapshotProvider(content: .mealPlan)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日膳食")
        .description("今天要做的菜")
        .supportedFamilies(allFamilies)
    }
}

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryShopping", provider: SnapshotProvider(content: .shopping)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("购物清单")
        .description("待买清单,可直接勾选")
        .supportedFamilies(allFamilies)
    }
}

struct WasteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryWaste", provider: SnapshotProvider(content: .waste)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("减废成效")
        .description("用掉率与减废统计")
        .supportedFamilies(allFamilies)
    }
}
