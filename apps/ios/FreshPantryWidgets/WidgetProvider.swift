import AppIntents
import WidgetKit

/// 一条时间线条目:渲染时刻 + 内容类别 + 四类快照合集。内容类别来源:固定 widget
/// 由其 `SnapshotProvider(content:)` 注入;可配置 widget 由 `SelectWidgetContentIntent`
/// 注入。视图统一读 `entry.content`。
struct WidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetContentChoice
    let bundle: WidgetSnapshotBundle
    /// App Group 里还没有 app 发布的快照(用户尚未启动过 app)→ 显示「打开 app」占位。
    let needsAppLaunch: Bool
}

/// 共享取数:**只读** App Group 里 app 预算好的快照——不在 widget 进程碰 SwiftData。
private func makeWidgetEntry(content: WidgetContentChoice, now: Date) -> WidgetEntry {
    guard let bundle = WidgetSnapshotStore.read() else {
        return WidgetEntry(date: now, content: content, bundle: .empty, needsAppLaunch: true)
    }
    return WidgetEntry(date: now, content: content, bundle: bundle, needsAppLaunch: false)
}

/// 下次刷新:跨午夜(临期剩余天数每天重算);app 在数据变更时另会显式 reload。
private func nextWidgetReload(after now: Date) -> Date {
    Calendar.current.nextDate(
        after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
    ) ?? now.addingTimeInterval(6 * 3600)
}

/// 固定 widget 的 provider(普通 `TimelineProvider`,内容类别由实例固定)。
/// 每个固定 widget 用 `SnapshotProvider(content: .shopping)` 等注入自己那类。
struct SnapshotProvider: TimelineProvider {
    let content: WidgetContentChoice

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: content, bundle: .empty, needsAppLaunch: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeWidgetEntry(content: content, now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: [makeWidgetEntry(content: content, now: now)], policy: .after(nextWidgetReload(after: now))))
    }
}

/// 可配置 widget 的 provider(`AppIntentTimelineProvider`,内容类别来自配置 intent)。
/// ⚠️ 真机 Release 是否认该配置待验证;作为「补充」与 4 个固定 widget 并存,
/// 即便不可配置也不影响固定 widget。
struct ConfigurableSnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: .expiring, bundle: .empty, needsAppLaunch: false)
    }

    func snapshot(for configuration: SelectWidgetContentIntent, in context: Context) async -> WidgetEntry {
        makeWidgetEntry(content: configuration.content, now: .now)
    }

    func timeline(for configuration: SelectWidgetContentIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let now = Date.now
        return Timeline(entries: [makeWidgetEntry(content: configuration.content, now: now)], policy: .after(nextWidgetReload(after: now)))
    }
}
