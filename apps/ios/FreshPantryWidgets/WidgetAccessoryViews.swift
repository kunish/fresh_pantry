import SwiftUI
import WidgetKit

/// accessoryCircular:按内容类别的环形摘要。
struct AccessoryCircularView: View {
    let entry: WidgetEntry
    var body: some View {
        switch entry.content {
        case .expiring:
            gauge(value: entry.bundle.expiring.needsAttentionCount, max: 9,
                  symbol: "exclamationmark.triangle", label: "\(entry.bundle.expiring.needsAttentionCount)")
                .widgetURL(URL(string: contentDeepLink(.expiring)))
        case .mealPlan:
            gauge(value: entry.bundle.mealPlan.items.count, max: 9,
                  symbol: "fork.knife", label: "\(entry.bundle.mealPlan.items.count)")
                .widgetURL(URL(string: contentDeepLink(.mealPlan)))
        case .shopping:
            gauge(value: entry.bundle.shopping.uncheckedCount, max: 9,
                  symbol: "cart", label: "\(entry.bundle.shopping.uncheckedCount)")
                .widgetURL(URL(string: contentDeepLink(.shopping)))
        case .waste:
            Gauge(value: Double(min(max(entry.bundle.waste.useUpPercent, 0), 100)), in: 0...100) {
                Image(systemName: "leaf")
            } currentValueLabel: {
                Text("\(entry.bundle.waste.useUpPercent)")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetURL(URL(string: contentDeepLink(.waste)))
        }
    }

    private func gauge(value: Int, max: Int, symbol: String, label: String) -> some View {
        Gauge(value: Double(min(value, max)), in: 0...Double(max)) {
            Image(systemName: symbol)
        } currentValueLabel: {
            Text(label)
        }
        .gaugeStyle(.accessoryCircular)
    }
}

/// accessoryRectangular:按内容类别的一行摘要。
struct AccessoryRectangularView: View {
    let entry: WidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.content {
            case .expiring:
                Label("临期 \(entry.bundle.expiring.needsAttentionCount) 件", systemImage: "exclamationmark.triangle")
                if let first = entry.bundle.expiring.items.first {
                    Text(first.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .mealPlan:
                Label("今日 \(entry.bundle.mealPlan.items.count) 顿", systemImage: "fork.knife")
                if let first = entry.bundle.mealPlan.items.first {
                    Text(first.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .shopping:
                Label("待买 \(entry.bundle.shopping.uncheckedCount) 项", systemImage: "cart")
                if let first = entry.bundle.shopping.items.first(where: { !$0.isChecked }) {
                    Text(first.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .waste:
                Label("用掉率 \(entry.bundle.waste.useUpPercent)%", systemImage: "leaf")
            }
        }
        .widgetURL(URL(string: contentDeepLink(entry.content)))
    }
}

/// accessoryInline:按内容类别的一句话。
struct AccessoryInlineView: View {
    let entry: WidgetEntry
    var body: some View {
        Text(inlineText)
            .widgetURL(URL(string: contentDeepLink(entry.content)))
    }
    private var inlineText: String {
        switch entry.content {
        case .expiring: return "临期 \(entry.bundle.expiring.needsAttentionCount) 件"
        case .mealPlan: return "今日 \(entry.bundle.mealPlan.items.count) 顿"
        case .shopping: return "待买 \(entry.bundle.shopping.uncheckedCount) 项"
        case .waste: return "用掉率 \(entry.bundle.waste.useUpPercent)%"
        }
    }
}

func contentDeepLink(_ content: WidgetContentChoice) -> String {
    switch content {
    case .expiring: return "freshpantry://expiring"
    case .mealPlan: return "freshpantry://mealplan"
    case .shopping: return "freshpantry://shopping"
    case .waste: return "freshpantry://waste"
    }
}
