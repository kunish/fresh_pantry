import Foundation

/// 跨进程「待落库的购物勾选」队列(App Group 内一份小 JSON)。
///
/// widget 交互勾选**不再**在 widget 进程里打开 SwiftData(那会把整个数据层 +
/// SwiftData 框架链进 widget 扩展,在真机约 30MB 预算里启动即超限被 jetsam →
/// 组件停在占位)。改为:widget 只 append 一条 itemID 到这里 + 就地补丁展示快照;
/// **app** 下次前台把队列里的翻转真正落库(经 `ShoppingToggleService`)并清空。
/// 纯 Foundation,无任何重框架。
enum WidgetPendingToggleStore {
    private static let fileName = "widget-pending-toggles.json"

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedDefaults.appGroupID)?
            .appending(path: fileName)
    }

    private static func read() -> [String] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }

    private static func write(_ ids: [String]) {
        guard let url = fileURL(), let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// **widget 侧**:追加一条待落库翻转(每次点击一条;同项重复点击各记一条,
    /// app 按序回放即与点击次数一致)。
    static func enqueue(itemID: String) {
        guard !itemID.isEmpty else { return }
        write(read() + [itemID])
    }

    /// **app 侧**:取出并清空队列,返回待落库的 itemID(按入队顺序)。
    static func drain() -> [String] {
        let ids = read()
        guard !ids.isEmpty else { return [] }
        write([])
        return ids
    }
}
