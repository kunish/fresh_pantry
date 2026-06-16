/// widget 内容类别(临期/今日膳食/购物/减废)。每个固定 widget 对应一类,视图按类分发。
///
/// 历史:曾用 `AppEnum` + `SelectWidgetContentIntent`(`WidgetConfigurationIntent`)做单个
/// 可配置 widget,但 **`AppIntentConfiguration` 在真机 Release 包上不工作**——iOS 不解析
/// 配置 intent,组件既无「编辑小组件」、timeline 也调不起来(空白),而 `StaticConfiguration`
/// 固定 widget 完全正常(多次真机验证 + widget-only intent / 换 kind 均未能救活)。故弃用
/// 可配置方案,改为每类一个独立固定 widget;本枚举退化为普通枚举,仅内部按类分发视图。
enum WidgetContentChoice {
    case expiring, mealPlan, shopping, waste
}
