import AppIntents

/// widget 内容类别。固定 widget(临期/今日膳食/购物/减废各一个)按类分发视图;
/// 另有一个可配置 widget 用 `SelectWidgetContentIntent` 让用户切换内容。
///
/// ⚠️ 真机 Release 包是否认这个 `WidgetConfigurationIntent` 配置尚待验证(此前单个
/// 可配置 widget 在真机长按无「编辑小组件」、卡默认内容)。因此可配置 widget 仅作
/// 「补充」与 4 个 StaticConfiguration 固定 widget 并存:即便真机不可配置,固定
/// widget 仍可靠工作。
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
