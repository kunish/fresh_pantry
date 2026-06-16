import Foundation
import WidgetKit

/// 单一刷新 seam:app 在数据可能变化时让所有时间线重载。集中在此,既便于
/// 将来扩展(按 kind 精细刷新),也避免散落的 WidgetKit 调用。
enum WidgetRefreshCoordinator {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
