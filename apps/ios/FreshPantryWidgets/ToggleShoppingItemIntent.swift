import AppIntents
import WidgetKit

/// widget 内勾选购物项。运行在 widget 进程,**不碰 SwiftData**(避免把数据层 +
/// SwiftData 框架链进扩展、启动即超内存被杀)。只做两件轻活:① 记一条待落库翻转
/// 到 App Group 队列;② 就地补丁展示快照让重载后即时反映。app 下次前台经
/// `ShoppingToggleService` 把队列真正落库 + 推送 outbox。
struct ToggleShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource { "勾选购物项" }

    @Parameter(title: "itemID")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        WidgetPendingToggleStore.enqueue(itemID: itemID)
        WidgetSnapshotStore.toggleShoppingItem(itemID: itemID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
