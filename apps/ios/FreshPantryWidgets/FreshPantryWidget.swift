import SwiftUI
import WidgetKit

struct FreshPantryWidget: Widget {
    static let kind = "FreshPantryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectWidgetContentIntent.self,
            provider: WidgetProvider()
        ) { entry in
            WidgetRootView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fresh Pantry")
        .description("临期 / 今日膳食 / 购物 / 减废,一眼掌握")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
