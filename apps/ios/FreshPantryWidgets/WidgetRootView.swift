import SwiftUI
import WidgetKit

struct WidgetRootView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.needsAppLaunch {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                Text("打开 Fresh Pantry").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(snapshot: entry.bundle.expiring)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(snapshot: entry.bundle.expiring)
        default:
            switch entry.content {
            case .expiring: ExpiringWidgetView(snapshot: entry.bundle.expiring, family: family)
            case .mealPlan: MealPlanWidgetView(snapshot: entry.bundle.mealPlan, family: family)
            case .shopping: ShoppingWidgetView(snapshot: entry.bundle.shopping, family: family)
            case .waste: WasteWidgetView(snapshot: entry.bundle.waste, family: family)
            }
        }
    }
}
