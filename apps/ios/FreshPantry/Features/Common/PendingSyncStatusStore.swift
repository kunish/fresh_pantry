import Foundation

/// Per-row sync visibility: holds the set of `entityID`s that currently have a
/// queued (not yet acknowledged) outbox operation, so list rows can show a
/// 「待同步」 badge without each one querying the outbox.
///
/// WHY a shared store (not a per-view fetch): the inventory / shopping lists
/// share ONE pending set, refreshed at the same natural sync moments the global
/// `SyncStatusBanner` count is — foreground, remote-merge pulse, back-online,
/// and after a local enqueue. A single pull → local membership test keeps the
/// badge O(1) per row regardless of list length.
///
/// READ-ONLY: this never writes to the outbox, so it can't perturb sync
/// semantics — it only surfaces state the write path already produced. Local
/// mutations still flow through `SyncWriter`'s outbox path unchanged; this store
/// just re-reads the result.
@Observable
@MainActor
final class PendingSyncStatusStore {
    /// The entityIDs with a queued outbox op. Membership = 「待同步」. A row whose
    /// id isn't here is fully synced (or local-only) → no badge, no noise.
    private(set) var pendingEntityIDs: Set<String> = []

    private let outbox: PendingSyncReading

    init(outbox: PendingSyncReading) {
        self.outbox = outbox
    }

    /// True when `entityID` has at least one queued outbox op. Blank ids never
    /// match (a freshly-created local row with no id can't be in the outbox).
    func isPending(_ entityID: String) -> Bool {
        guard !entityID.isEmpty else { return false }
        return pendingEntityIDs.contains(entityID)
    }

    /// Re-reads the pending set from the outbox. Best-effort: a failed read keeps
    /// the last good set rather than flashing every badge off (the next refresh
    /// trigger corrects it). Called from the same hooks that refresh the banner
    /// count — see `RootView`.
    func refresh() async {
        guard let ids = try? await outbox.pendingEntityIDs() else { return }
        pendingEntityIDs = ids
    }
}
