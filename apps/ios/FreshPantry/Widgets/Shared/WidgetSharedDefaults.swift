import Foundation

/// 主 app 与小组件扩展之间的跨进程身份通道(App Group `UserDefaults`)。
///
/// app 在启动 + 家庭切换时写入当前 household / clientId;widget 的
/// `WidgetDataReader`(查询作用域)与 `ToggleShoppingItemIntent`(构造 outbox
/// 操作的 householdId/clientId)读取它。store 本身走共享 SwiftData 容器;这里
/// 只搬运两个标量身份值。
enum WidgetSharedDefaults {
    /// 主 app 与 widget 共用的 App Group。须与两个 target 的
    /// `.entitlements` 里的 `application-groups` 一致。
    static let appGroupID = "group.com.kunish.freshPantry"

    private static let householdIDKey = "widget.householdID"
    private static let clientIDKey = "widget.clientID"

    /// 共享 suite;App Group 未授权(如本地未签名 dev)时为 nil。
    static var suite: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// 写当前作用域身份。`into` 可注入测试 suite;默认走共享 suite。
    static func writeIdentity(householdID: String, clientID: String, into defaults: UserDefaults? = WidgetSharedDefaults.suite) {
        guard let defaults else { return }
        defaults.set(householdID, forKey: householdIDKey)
        defaults.set(clientID, forKey: clientIDKey)
    }

    static func readHouseholdID(from defaults: UserDefaults? = WidgetSharedDefaults.suite) -> String {
        defaults?.string(forKey: householdIDKey) ?? ""
    }

    static func readClientID(from defaults: UserDefaults? = WidgetSharedDefaults.suite) -> String {
        defaults?.string(forKey: clientIDKey) ?? ""
    }
}
