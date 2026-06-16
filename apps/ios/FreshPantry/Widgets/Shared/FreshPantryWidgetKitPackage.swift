import AppIntents

/// 把本 framework 内定义的 AppIntents(`ToggleShoppingItemIntent` /
/// `SelectWidgetContentIntent`)的元数据**聚合进链接它的消费方 bundle**(主 app +
/// widget 扩展)。app 与 widget 各自声明一个 `AppIntentsPackage` 并在 `includedPackages`
/// 里引用本类型,linkd 在构建时把本 framework 的 intent 元数据写进消费方 bundle 的
/// 聚合 `Metadata.appintents`。
///
/// 这是消除「intent 在 framework / 另一模块,消费方 bundle 元数据里却没有它」的官方机制
/// (WWDC23「Explore enhancements to App Intents」)。本案的关键诉求 = 让主 app bundle
/// 含 `FreshPantryWidgetKit.ToggleShoppingItemIntent` 元数据,chronod 后台执行交互 intent
/// (openAppWhenRun=NO)时才能在主 app bundle 命中,不再报「no metadata in com.kunish.freshPantry」。
public struct FreshPantryWidgetKitPackage: AppIntentsPackage {}
