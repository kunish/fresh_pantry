import Foundation

/// Holds the parsed id of a tapped Spotlight result (库存食材 / 食谱) until
/// `RootView` switches to the owning tab and forwards the id to its feature
/// view.
///
/// Producer = `FreshPantryApp`'s `.onContinueUserActivity(CSSearchableItemActionType)`;
/// consumer = `RootView` (its `.task(id: pendingItem)` consumes, switches tab,
/// and hands the id over via the pending-…ID bindings). Mirrors
/// `NotificationTapRouter`'s pending/consume/clear contract, including the
/// cold-start rule: the consumer must read via `.task(id:)` (fires on appear
/// AND on change) because the activity can be delivered before `RootView`
/// exists, in which case no `onChange` ever fires.
@Observable
@MainActor
final class SpotlightRouter {
    /// The tapped result's parsed id awaiting consumption; nil when none.
    private(set) var pendingItem: SpotlightItemID?

    /// Parses + stores a tapped result's `uniqueIdentifier`. A malformed
    /// identifier is ignored — there is nothing sane to route to, and it must
    /// not clobber a still-pending valid intent.
    func capture(identifier: String) {
        guard let item = SpotlightItemID(identifier: identifier) else { return }
        pendingItem = item
    }

    /// One-shot read: returns the pending id and clears it.
    func consume() -> SpotlightItemID? {
        let value = pendingItem
        pendingItem = nil
        return value
    }

    func clear() { pendingItem = nil }
}
