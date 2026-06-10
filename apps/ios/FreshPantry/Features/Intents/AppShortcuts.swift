import AppIntents

/// Exposes the app's intents to Siri / 快捷指令 / Spotlight with Chinese trigger
/// phrases. The system surfaces these automatically once the app is installed —
/// no extension target, no signing/App Group changes (the intents run in the main
/// app target).
///
/// Every `AppShortcutPhrase` MUST embed `\(.applicationName)` so Siri can scope
/// the phrase to this app; phrases without it are rejected at build time.
struct FreshPantryAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToShoppingListIntent(),
            phrases: [
                "用\(.applicationName)加到购物清单",
                "在\(.applicationName)里加到购物清单",
                "\(.applicationName)加购物清单",
            ],
            shortTitle: "加到购物清单",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: ExpiringFoodQueryIntent(),
            phrases: [
                "查\(.applicationName)临期食材",
                "\(.applicationName)什么快过期了",
                "用\(.applicationName)看临期食材",
            ],
            shortTitle: "查临期食材",
            systemImageName: "clock.badge.exclamationmark"
        )
    }
}
