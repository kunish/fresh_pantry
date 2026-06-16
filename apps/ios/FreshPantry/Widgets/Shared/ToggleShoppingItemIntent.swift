import AppIntents

/// widget 内勾选购物项。运行在 widget 进程,**不碰 SwiftData**(避免把数据层 +
/// SwiftData 框架链进扩展、启动即超内存被杀)。只做两件轻活:① 记一条待落库翻转
/// 到 App Group 队列;② 就地补丁展示快照让重载后即时反映。app 下次前台经
/// `ShoppingToggleService` 把队列真正落库 + 推送 outbox。
///
/// ⚠️ **此类型必须只存在于共享 framework `FreshPantryWidgetKit`(app+widget 都链接同一份)**:
/// 交互 widget 的 `Button(intent:)` 由 chronod 渲染时读 widget 扩展元数据即可,但
/// `openAppWhenRun=NO` 的**执行**阶段,chronod 按【主 app bundle id com.kunish.freshPantry】
/// 里的聚合元数据、用 LNAction 携带的【模块限定类型名】解析。若该 intent 被 app 与 widget
/// 各自编进自己的模块,会生成两个不同类型(FreshPantry.* 与 FreshPantryWidgets.*),
/// mangled 名不一致 → chronod 在 app bundle 命中不到 → 真机报
/// `"There is no metadata for ToggleShoppingItemIntent in com.kunish.freshPantry"`(只真机暴露)。
/// 收进单一 framework 模块后,两边引用同一个 `FreshPantryWidgetKit.ToggleShoppingItemIntent`,
/// 再由 AppIntentsPackage(见 FreshPantryWidgetKitPackage)把其元数据聚合进 app bundle。
public struct ToggleShoppingItemIntent: AppIntent {
    public static var title: LocalizedStringResource { "勾选购物项" }

    @Parameter(title: "itemID")
    public var itemID: String

    public init() {}
    public init(itemID: String) { self.itemID = itemID }

    public func perform() async throws -> some IntentResult {
        WidgetPendingToggleStore.enqueue(itemID: itemID)
        WidgetSnapshotStore.toggleShoppingItem(itemID: itemID)
        // 不显式 WidgetCenter.reloadAllTimelines():交互 AppIntent 的 perform 完成后,
        // 系统会对该 widget 保证一次立即 reload,届时重读上面已就地补丁的快照即反映勾选;
        // 而从扩展进程显式 reload 在真机会被节流(FB13152293),冗余且不可靠。
        return .result()
    }
}
