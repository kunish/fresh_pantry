import AppIntents
import WidgetKit

/// 用户在长按编辑 widget 时可选的内容。
enum WidgetContentChoice: String, AppEnum {
    case expiring, mealPlan, shopping, waste

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "组件内容" }
    static var caseDisplayRepresentations: [WidgetContentChoice: DisplayRepresentation] {
        [
            .expiring: "临期食材",
            .mealPlan: "今日膳食",
            .shopping: "购物清单",
            .waste: "减废成效",
        ]
    }
}

/// widget 配置 intent:选择展示哪类内容(默认临期)。
struct SelectWidgetContentIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "选择内容" }
    static var description: IntentDescription { "选择小组件展示的内容" }

    @Parameter(title: "内容", default: .expiring)
    var content: WidgetContentChoice
}
