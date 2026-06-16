import AppIntents
import SwiftUI
import WidgetKit
import FreshPantryWidgetKit

@main
struct FreshPantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExpiringWidget()
        MealPlanWidget()
        ShoppingWidget()
        WasteWidget()
        ConfigurableWidget()
    }
}

/// 把共享 framework 的 AppIntents 元数据(Toggle/Select)聚合进 **widget 扩展 bundle**,
/// 使 Button(intent:) 与 AppIntentConfiguration 引用的 `FreshPantryWidgetKit.*` 类型在
/// widget 端元数据中存在。app 端另有一份(见 FreshPantryApp),两边引用同一 framework 类型。
///
/// 用独立非隔离 struct 而非挂在 `@main WidgetBundle` 上:WidgetBundle 是 MainActor 隔离,
/// AppIntentsPackage 一致性跨隔离会触发 Swift6 ConformanceIsolation 错误。构建系统扫描
/// target 内任意 AppIntentsPackage 一致性即可,无需挂在入口类型。
struct FreshPantryWidgetsAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FreshPantryWidgetKitPackage.self] }
}
