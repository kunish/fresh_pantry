import AppIntents

/// widget 内勾选购物项。运行在 widget 进程,**不碰 SwiftData**(避免把数据层 +
/// SwiftData 框架链进扩展、启动即超内存被杀)。只做两件轻活:① 记一条待落库翻转
/// 到 App Group 队列;② 就地补丁展示快照让重载后即时反映。app 下次前台经
/// `ShoppingToggleService` 把队列真正落库 + 推送 outbox。
///
/// ⚠️ **此文件必须放在 `Widgets/Shared`(app + widget 双编译),不能只在 widget 扩展**:
/// 交互 widget 的 `Button(intent:)` 由 `chronod` 在 widget 进程渲染(读 widget 扩展的
/// AppIntents 元数据即可),但**执行**该 intent 时 chronod 是按【主 app bundle id】
/// (`com.kunish.freshPantry`)查找其元数据的。若 intent 只编进 widget 扩展,主 app
/// bundle 里没有它的元数据,真机点击会被 chronod 以
/// `"There is no metadata for ToggleShoppingItemIntent in com.kunish.freshPantry"`
/// 拒绝执行(表现为「点了没反应」)——只在真机暴露(模拟器不复现)。下沉 Shared 后
/// 主 app 的 `Metadata.appintents` 也含本 intent,chronod 执行查找即命中。
struct ToggleShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource { "勾选购物项" }

    @Parameter(title: "itemID")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        WidgetPendingToggleStore.enqueue(itemID: itemID)
        WidgetSnapshotStore.toggleShoppingItem(itemID: itemID)
        // 不显式 WidgetCenter.reloadAllTimelines():交互 AppIntent 的 perform 完成后,
        // 系统会对该 widget 保证一次立即 reload,届时重读上面已就地补丁的快照即反映勾选;
        // 而从扩展进程显式 reload 在真机会被节流(FB13152293),冗余且不可靠。
        return .result()
    }
}
