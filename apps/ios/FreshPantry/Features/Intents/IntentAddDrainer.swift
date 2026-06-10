import Foundation

/// Drains the `IntentPendingAddQueue` (item names captured by
/// `AddToShoppingListIntent`) through a live, fully-wired `ShoppingStore` so each
/// add lands in the CURRENT household scope with the real `syncWriter` (outbox
/// enqueue + push). This is the app-side half of the intent → app handoff that
/// keeps the add correct + synced (see `AddToShoppingListIntent`).
///
/// `@MainActor` because it builds and drives a `@MainActor ShoppingStore`. Wired
/// from `FreshPantryApp` keyed on `householdID`, so it runs only AFTER the active
/// household is resolved (a cold-start drain before sign-in would otherwise land
/// in the local-only "" scope).
@MainActor
enum IntentAddDrainer {
    /// Adds every queued name through a freshly-built store scoped to `householdID`
    /// (the same construction `ShoppingView` uses), then loads so dedup/merge runs.
    /// Builds the store ONLY when there's something to drain, to avoid needless work
    /// on every household change.
    static func drain(
        dependencies: AppDependencies,
        queue: IntentPendingAddQueue = IntentPendingAddQueue()
    ) async {
        let names = queue.peek()
        guard !names.isEmpty else { return }

        let store = ShoppingStore(
            repository: dependencies.shoppingRepository,
            householdID: dependencies.householdID,
            syncWriter: dependencies.syncWriter
        )
        await store.load()

        // Ack on success: only remove a name from the persisted queue once it has
        // actually landed (added/merged, or already present). `add` returns false
        // for BOTH an un-mergeable duplicate (already on the list → the user's
        // "add milk" intent is satisfied → consume) AND a genuine persist failure
        // (no row written → KEEP queued so the next foreground retries it rather
        // than silently dropping the Siri add the user already saw confirmed).
        var consumed: [String] = []
        for name in names {
            if await store.add(name: name) {
                consumed.append(name)
                continue
            }
            let key = ShoppingItemNormalizer.nameKey(name)
            let alreadyOnList = store.items.contains { ShoppingItemNormalizer.nameKey($0.name) == key }
            if alreadyOnList { consumed.append(name) } // duplicate, not a write failure
        }
        queue.remove(consumed)
    }
}
