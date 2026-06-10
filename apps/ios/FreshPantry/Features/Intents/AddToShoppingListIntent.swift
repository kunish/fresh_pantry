import AppIntents
import Foundation

/// Siri / 快捷指令 / Spotlight intent: 「把 X 加进购物清单」.
///
/// CONCURRENCY / CORRECTNESS DECISION — `openAppWhenRun = true`:
/// the add is intentionally NOT performed inside the intent process. The active
/// household id is resolved from the backend into the in-memory `SyncSession`
/// after sign-in and is never persisted to disk. A background container write
/// would therefore land in the local-only ("") scope and never sync to the
/// family — only join-time `adoptLocalDataIntoHousehold` migrates "" → household,
/// so a divergent local row would be silently invisible to other members. Rather
/// than ship an add that can drop the write, the intent enqueues the name
/// (`IntentPendingAddQueue`) and opens the app; the live, fully-wired
/// `ShoppingStore` drains the queue through its real `syncWriter`, guaranteeing
/// correct household scoping + outbox enqueue + sync. The Siri/Shortcuts/Spotlight
/// entry point is still delivered — the only cost is a brief app foreground.
struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "加到购物清单"

    static let description = IntentDescription("把一件商品加入购物清单。")

    /// Open the app so the add runs through the live store (see type doc).
    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "商品",
        description: "要加入购物清单的商品名称",
        requestValueDialog: IntentDialog("要加什么?")
    )
    var itemName: String

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$itemName) 加进购物清单")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Same normalization the store applies; a blank name surfaces a visible
        // error dialog (never a silent no-op).
        guard let name = IntentName.normalize(itemName) else {
            throw IntentError.emptyItemName
        }
        IntentPendingAddQueue().enqueue(name)
        // Nudge the (now-foregrounded) app to drain THIS session — the scene-phase
        // drains alone can miss when `.active` fires before this enqueue or the
        // app was already active. See `Notification.Name.intentDidEnqueueShoppingAdd`.
        NotificationCenter.default.post(name: .intentDidEnqueueShoppingAdd, object: nil)
        return .result(dialog: IntentDialog("已把\(name)加进购物清单"))
    }
}

/// User-facing intent errors. Conforms to `CustomLocalizedStringResourceConvertible`
/// so Siri/Shortcuts speak/show the Chinese message instead of a generic failure.
enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case emptyItemName
    case noInventory

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyItemName:
            return "没听清要加什么,请再说一次商品名称。"
        case .noInventory:
            return "暂时读不到库存,请打开 App 后再试。"
        }
    }
}
