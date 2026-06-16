import SwiftUI
import WidgetKit

/// Widget bundle 入口。后续任务会用真实的 `FreshPantryWidget` 替换占位实现。
@main
struct FreshPantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

private struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryPlaceholder", provider: PlaceholderProvider()) { _ in
            Text("Fresh Pantry")
        }
        .supportedFamilies([.systemSmall])
    }
}

private struct PlaceholderEntry: TimelineEntry { let date: Date }

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
