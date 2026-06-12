import Foundation

/// The app-root sync session: the active household scope every store enqueues
/// against, plus a stable per-install client id stamped on every wire write.
///
/// Ported from the root-resident `selectedHouseholdIdProvider` +
/// `syncClientIdProvider` in `lib/sync/sync_providers.dart`.
///
/// INVARIANT (parity #5): `selectedHouseholdId` MUST be a single instance owned
/// at the app root and injected once via `.environment`. The mutating stores
/// (inventory, shopping, custom recipes, meal plan) are all root-resident, so
/// they read THIS instance when deciding whether to enqueue a sync op. A
/// per-screen / nested `SyncSession` would be a different object: those stores
/// would still read the root default (`""` = local-only), `enqueueSync` would
/// silently no-op (empty household → no enqueue → no push), and the write would
/// never reach other household members. Never construct a second `SyncSession`
/// for a screen — pass the root one down.
@Observable
@MainActor
final class SyncSession {
    /// The household every store syncs to, or `""` for local-only / personal
    /// mode. The auth/session layer projects the active household here; the
    /// stores read it through this single root-owned instance (see invariant
    /// above). Mutable so the session can switch households.
    ///
    /// Persisted on every assignment and restored at init, so a cold launch
    /// reads the household-scoped local rows BEFORE any network round-trip —
    /// without this, the scope sat at `""` until `refreshHouseholds()`
    /// returned, showing an empty app over full on-disk data (and never
    /// recovering offline). `refreshHouseholds` still corrects the scope once
    /// online (switch / removal / sign-out all overwrite + persist).
    var selectedHouseholdId: String {
        didSet { defaults.set(selectedHouseholdId, forKey: Self.selectedHouseholdIdKey) }
    }

    /// A stable per-install identifier stamped on every wire write's
    /// `client_id` column. Unlike the Dart constant `"local-client"` (which made
    /// every device indistinguishable), the Swift port mints a per-install
    /// UUID on first launch and reuses it thereafter, so writes can be
    /// attributed to the originating install. Lowercase UUID-v4 shape, matching
    /// the ids minted for local-only rows on household join.
    let clientId: String

    /// UserDefaults key the per-install client id is persisted under. Fixed so
    /// the id survives across launches; never changes once written.
    static let clientIdKey = "fresh_pantry.sync.client_id"

    /// UserDefaults key the active household scope is persisted under, so a
    /// relaunch restores the last scope (offline-first) instead of waiting on
    /// the networked household query.
    static let selectedHouseholdIdKey = "fresh_pantry.sync.selected_household_id"

    /// The store both persisted values live in. Injectable for test isolation.
    private let defaults: UserDefaults

    /// A monotonically-increasing "remote data changed" pulse. The
    /// `HouseholdContentSyncCoordinator` bumps this AFTER it writes merged remote
    /// rows into the local repos (initial bulk pull or a realtime snapshot); the
    /// feature views observe it (`.onChange`) to reload their stores. Coarse but
    /// correct — any remote merge refreshes the visible lists. `@Observable`
    /// already, so a change re-runs dependent `onChange`/body reads.
    private(set) var dataRevision: Int = 0

    /// Signals a completed remote merge. Called on the main actor by the content
    /// sync coordinator after a successful local write of merged remote rows.
    func bumpDataRevision() { dataRevision += 1 }

    /// A lightweight "an outbound push just ran" pulse — bumped by `SyncWriter`
    /// after the enqueue-triggered push completes. Distinct from `dataRevision`
    /// so observers can refresh ONLY the per-item 待同步 badges (re-reading the
    /// outbox) without forcing every feature store to reload. Without it, a row's
    /// badge would stay lit after a successful background push until the next
    /// foreground / reconnect / inbound merge.
    private(set) var pendingSyncRevision: Int = 0

    /// Signals that an outbound push cycle finished (ops were acked or left
    /// queued); observers re-read the pending-outbox set to converge the badges.
    func bumpPendingSyncRevision() { pendingSyncRevision += 1 }

    /// - Parameters:
    ///   - selectedHouseholdId: initial scope. The default `""` means "restore
    ///     the persisted scope" (local-only when nothing was persisted); an
    ///     explicit non-empty id is a seed (tests / previews) that wins for
    ///     this instance WITHOUT touching the persisted value — only runtime
    ///     assignments persist (`didSet` never fires during init), so a seeded
    ///     test container can't pollute the host's `.standard` scope.
    ///   - defaults: the store both ids are persisted in. Injectable so
    ///     tests can use an isolated suite instead of `.standard`.
    init(selectedHouseholdId: String = "", defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedHouseholdId = selectedHouseholdId.isEmpty
            ? (defaults.string(forKey: Self.selectedHouseholdIdKey) ?? "")
            : selectedHouseholdId
        self.clientId = Self.resolveClientId(defaults: defaults)
    }

    /// Returns the persisted per-install client id, minting + storing a fresh
    /// lowercase UUID-v4 on first launch. Stable across instances sharing the
    /// same `defaults` suite.
    private static func resolveClientId(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: clientIdKey), !existing.isEmpty {
            return existing
        }
        let minted = UUID().uuidString.lowercased()
        defaults.set(minted, forKey: clientIdKey)
        return minted
    }
}
