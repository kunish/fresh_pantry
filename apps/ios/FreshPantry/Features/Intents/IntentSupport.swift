import Foundation

/// Shared support for the App Intents (Siri / 快捷指令 / Spotlight entry points).
///
/// Two concerns live here, both pure or persistence-only so they can be unit
/// tested without the AppIntents runtime:
///
///  - `IntentName`: shopping-name normalization + empty validation (mirrors the
///    `name.trimmed` + `!isEmpty` guard `ShoppingStore.add` applies).
///  - `IntentPendingAddQueue`: a tiny `UserDefaults`-backed FIFO of item names
///    captured by `AddToShoppingListIntent`. The add is NOT performed inside the
///    intent: the active household id is resolved from the network into the
///    in-memory `SyncSession` after sign-in and is never persisted to disk, so a
///    background container write would land in the local-only ("") scope and
///    never reach the family (only join-time `adoptLocalDataIntoHousehold`
///    migrates "" → household). Instead the intent enqueues the name and opens
///    the app; the live, fully-wired `ShoppingStore` drains the queue through its
///    real `syncWriter`, guaranteeing correct household scoping + outbox enqueue
///    + sync. See `AddToShoppingListIntent` for the `openAppWhenRun = true`
///    rationale.

extension Notification.Name {
    /// Posted (in-process) by `AddToShoppingListIntent` right after it enqueues a
    /// name, so the foregrounded app drains it THIS session regardless of
    /// scene-phase timing. `openAppWhenRun = true` runs `perform()` in the app
    /// process AFTER the app is already foregrounded, so a `.active` transition
    /// may fire before the enqueue (and a Shortcuts run while the app is already
    /// active fires no `.active` at all) — this signal closes that gap.
    static let intentDidEnqueueShoppingAdd = Notification.Name("fresh_pantry.intent.didEnqueueShoppingAdd")
}

/// Shopping item-name normalization for the intents — the SAME shape
/// `ShoppingStore.add` enforces (trim, reject blank). Kept pure so the validation
/// is unit-testable without the AppIntents runtime.
enum IntentName {
    /// Trims surrounding whitespace; returns nil when the result is empty so the
    /// caller surfaces a visible error dialog instead of silently enqueuing junk.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A `UserDefaults`-backed FIFO of shopping item names captured by the add intent
/// and drained by the live `ShoppingStore` on next foreground. JSON-encoded array
/// under one key so a read-modify-write stays atomic enough for the
/// (single-writer-at-a-time) intent → app handoff.
struct IntentPendingAddQueue {
    /// Key the pending names array is persisted under. Fixed so a name enqueued
    /// by the intent survives until the app drains it.
    static let storageKey = "fresh_pantry.intents.pending_shopping_adds"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Appends a name to the queue (already-normalized by the caller). Read the
    /// current array, append, write back.
    func enqueue(_ name: String) {
        var names = load()
        names.append(name)
        save(names)
    }

    /// Removes the given names (one matching occurrence each) from the queue,
    /// leaving anything else untouched. The drainer's "ack on success" path: only
    /// names that actually landed in the store are removed, so a persist failure
    /// keeps its name queued for the next foreground retry instead of dropping it.
    /// Removing by value (not clearing) also preserves any name enqueued by a
    /// concurrent intent invocation mid-drain.
    func remove(_ namesToRemove: [String]) {
        guard !namesToRemove.isEmpty else { return }
        var remaining = load()
        for name in namesToRemove {
            if let index = remaining.firstIndex(of: name) { remaining.remove(at: index) }
        }
        if remaining.isEmpty { defaults.removeObject(forKey: Self.storageKey) }
        else { save(remaining) }
    }

    /// Current queued names without clearing (for tests / inspection).
    func peek() -> [String] { load() }

    private func load() -> [String] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return names
    }

    private func save(_ names: [String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Pure selection of items expiring within `withinDays` calendar days, returning
/// display names ordered soonest-first. Reuses `ExpiryCalculator.daysUntilExpiry`
/// — the SAME canonical local-date day math the freshness tiers use — so the
/// "临期" window stays defined in one place. Items without an expiry date are
/// excluded (no expiry = "保质期未知/无限期", never "快过期").
enum ExpiringFoodSelector {
    /// Default lookahead window for "什么快过期了" — three calendar days. Distinct
    /// from `ExpiryCalculator.urgentWithinDays` (the 2-day `.urgent` tier): the
    /// query intentionally casts a slightly wider net for "用掉它" planning.
    static let defaultWithinDays = 3

    /// Names of items expiring within `withinDays` days (inclusive), soonest
    /// first, then by name for a stable tie-break. Already-expired items
    /// (`days < 0`) ARE included (they most urgently need attention).
    static func expiringNames(
        in items: [Ingredient],
        withinDays: Int = defaultWithinDays,
        now: Date = Date()
    ) -> [String] {
        items
            .compactMap { item -> (name: String, days: Int)? in
                guard let expiry = item.expiryDate else { return nil }
                let days = ExpiryCalculator.daysUntilExpiry(expiry, now: now)
                guard days <= withinDays else { return nil }
                let name = item.name.trimmed
                guard !name.isEmpty else { return nil }
                return (name, days)
            }
            .sorted { lhs, rhs in
                if lhs.days != rhs.days { return lhs.days < rhs.days }
                return lhs.name < rhs.name
            }
            .map(\.name)
    }
}
