import AppIntents
import SwiftUI
import WidgetKit

// 交互/配置 widget 的 AppIntents(Toggle/Select)经 dual-target membership 直接编进本
// widget 扩展 target(源在 Widgets/Shared,见 project.yml),widget 端元数据自带;app 端
// 另有一份(同源各编一次)。两边模块名不同但匹配按 identifier 自洽。无需 AppIntentsPackage。

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
