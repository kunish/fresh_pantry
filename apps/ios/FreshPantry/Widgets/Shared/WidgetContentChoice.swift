import AppIntents

/// widget 内容类别。固定 widget(临期/今日膳食/购物/减废各一个)按类分发视图;
/// 另有一个可配置 widget 用 `SelectWidgetContentIntent` 让用户切换内容。
///
/// ⚠️ 与 `ToggleShoppingItemIntent` 同理:配置 intent `SelectWidgetContentIntent` 的元数据
/// 必须能被系统的运行时 AppIntents 索引发现,AppIntentConfiguration 才能渲染配置 / 出
/// 「编辑小组件」。故本文件经 dual-target membership 直接编进 app + widget 两个 target
/// (见 project.yml),由两个 target 各自的标准抽取/注册路径写进运行时索引 —— **不走
/// framework**。此前它在 framework 里时,release 真机表现为可配置 widget 占位 + 长按无
/// 「编辑小组件」(同 FB #425:framework 的 intent 元数据 release 下不被 linkd 注册)。
public enum WidgetContentChoice: String, AppEnum {
    case expiring, mealPlan, shopping, waste

    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "组件内容" }
    public static var caseDisplayRepresentations: [WidgetContentChoice: DisplayRepresentation] {
        [
            .expiring: "临期食材",
            .mealPlan: "今日膳食",
            .shopping: "购物清单",
            .waste: "减废成效",
        ]
    }
}

/// widget 配置 intent:选择展示哪类内容(默认临期)。
public struct SelectWidgetContentIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "选择内容" }
    public static var description: IntentDescription { "选择小组件展示的内容" }

    @Parameter(title: "内容", default: .expiring)
    public var content: WidgetContentChoice

    public init() {}
}
