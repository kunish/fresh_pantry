import AppIntents

/// widget 内勾选购物项。`openAppWhenRun=NO`,由 chronod 在**主 app 进程**(app 运行/可唤醒
/// 时)后台执行,**刻意不碰 SwiftData**:perform 可能在受限的后台上下文跑,只做两件轻活
/// ① 记一条待落库翻转到 App Group 队列;② 就地补丁展示快照让重载后即时反映。app 下次前台
/// 经 `WidgetPendingToggleDrainer`→`ShoppingToggleService` 把队列真正落库 + 推送 outbox。
///
/// ⚠️ **此源文件经 dual-target membership 同时编进【主 app target】与【widget 扩展 target】**
/// (见 project.yml:app 不再 exclude Widgets/Shared,widget 的 sources 也加 Widgets/Shared),
/// **不走任何 framework**。这是 Apple DTS / 官方 sample 对交互式 widget AppIntent 的指定做法。
/// 缘由:chronod 执行 `openAppWhenRun=NO` 交互 intent 时,按【主 app bundle com.kunish.freshPantry】
/// 里的 AppIntents **运行时索引**(linkd/appintentsd 安装时注册)按 **identifier**
/// "ToggleShoppingItemIntent" 查找;intent 必须随 app 自身模块被标准抽取/注册,系统在
/// release/TestFlight 下才会索引它。
///   收进共享 framework(动态或 staticlib)行不通:元数据文件虽能合并进 app bundle,但 release
///   下 linkd 不把 framework/AppIntentsPackage 的 intent 注册进运行时索引(FB #425),真机恒报
///   `"There is no metadata for ToggleShoppingItemIntent in com.kunish.freshPantry"`(删+重启+
///   重装不消失=已排除缓存)。dual-membership 下 app 模块是 `FreshPantry.*`、widget 模块是
///   `FreshPantryWidgets.*`,mangled 名不同但**不失配**:匹配按 identifier,各 bundle 自洽。
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
