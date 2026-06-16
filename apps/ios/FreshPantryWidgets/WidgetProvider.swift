import SwiftData
import WidgetKit

/// 一条时间线条目:渲染时刻 + 选中内容 + 四类快照合集。
struct WidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetContentChoice
    let bundle: WidgetSnapshotBundle
    /// App Group store 尚不存在(用户未首启完成迁移)→ 显示「打开 app」占位。
    let needsAppLaunch: Bool
}

struct WidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: .expiring, bundle: .empty, needsAppLaunch: false)
    }

    func snapshot(for configuration: SelectWidgetContentIntent, in context: Context) async -> WidgetEntry {
        await entry(for: configuration.content, family: context.family, now: .now)
    }

    func timeline(for configuration: SelectWidgetContentIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let now = Date.now
        let current = await entry(for: configuration.content, family: context.family, now: now)
        // 下次刷新:跨午夜(临期剩余天数每天重算)。app 在数据变更时另会显式 reload。
        let nextMidnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(6 * 3600)
        return Timeline(entries: [current], policy: .after(nextMidnight))
    }

    /// 读共享容器 + 当前家庭作用域,**只派生当前 family + 选中内容需要的那一类快照**
    /// (widget 进程约 30MB 内存上限,算全四类会被 jetsam 杀掉 → 停在占位)。
    /// 容器不存在 → needsAppLaunch。
    private func entry(for content: WidgetContentChoice, family: WidgetFamily, now: Date) async -> WidgetEntry {
        guard let container = ModelContainerFactory.makeSharedExisting() else {
            return WidgetEntry(date: now, content: content, bundle: .empty, needsAppLaunch: true)
        }
        let householdID = WidgetSharedDefaults.readHouseholdID()
        let reader = WidgetDataReader(container: container)
        let bundle = await reader.bundle(for: content, family: family, householdID: householdID, now: now)
        return WidgetEntry(date: now, content: content, bundle: bundle, needsAppLaunch: false)
    }
}
