import Foundation
import os

/// The single seam every mutating store / controller uses to record an outbox
/// op then kick a (coalesced) push. Mirrors the Flutter `SyncEnqueue` mixin in
/// `lib/sync/sync_enqueue.dart`.
///
/// LOCAL-FIRST CONTRACT: enqueue is a NO-OP (not a dropped write) when no
/// household is selected (`selectedHouseholdId` empty → personal/local-only
/// mode) or the op's `entityId` is blank — mirrors Dart `enqueueSync`'s empty
/// household / empty entity guards. A no-op here is the correct local-first
/// behaviour, not a swallowed failure.
///
/// `coordinator` is nil in local-only mode (no `SupabaseClient`): ops are still
/// recorded so they flush once a backend / household is wired, but no push runs.
@MainActor
final class SyncWriter {
    /// One outbox op to record. The store/controller fills in the wire patch
    /// (`DomainJSON.valueMap` of the resulting row) and the optimistic-lock
    /// `baseVersion` (the mutated row's `remoteVersion`; nil for a fresh create).
    struct PendingOp {
        var entityType: SyncEntityType
        var entityId: String
        var operation: SyncOperationType
        var patch: [String: JSONValue]
        var baseVersion: Int?
    }

    private static let logger = Logger(subsystem: "com.kunish.freshPantry", category: "sync")

    private let outbox: SyncOutboxRepository
    /// nil in local-only mode (no client) — ops are recorded but never pushed.
    /// Held behind the `CoordinatorPushing` seam (not the concrete actor) so the
    /// trailing push is assertable with a spy — the gap that hid `c0defc8` /
    /// `dabcbd4`.
    private let coordinator: CoordinatorPushing?
    private let session: SyncSession

    init(outbox: SyncOutboxRepository, coordinator: CoordinatorPushing?, session: SyncSession) {
        self.outbox = outbox
        self.coordinator = coordinator
        self.session = session
    }

    /// Records ONE op then kicks a (coalesced) push. No-op — the correct
    /// local-first behaviour, not a dropped write — when no household is selected
    /// or `entityId` is blank.
    func enqueue(
        entityType: SyncEntityType,
        entityId: String,
        operation: SyncOperationType,
        patch: [String: JSONValue],
        baseVersion: Int?
    ) async {
        await enqueueBatch([
            PendingOp(
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                patch: patch,
                baseVersion: baseVersion
            )
        ])
    }

    /// Records each op IN ORDER (no per-op push), then ONE trailing push. Used by
    /// the Intake/Deduction apply that lands multiple rows. Same no-op guard as
    /// `enqueue`: skips entirely when no household is selected, and skips any
    /// individual op whose `entityId` is blank.
    func enqueueBatch(_ ops: [PendingOp]) async {
        guard !session.selectedHouseholdId.isEmpty else { return }

        var recordedAny = false
        for op in ops {
            guard !op.entityId.trimmed.isEmpty else { continue }
            let operation = SyncOperation(
                id: UUID().uuidString.lowercased(),
                householdId: session.selectedHouseholdId,
                entityType: op.entityType,
                entityId: op.entityId,
                operation: op.operation,
                patch: op.patch,
                baseVersion: op.baseVersion,
                clientId: session.clientId,
                createdAt: Date()
            )
            do {
                try await outbox.enqueue(operation)
                recordedAny = true
            } catch {
                // SwiftData write failed (disk full, migration mismatch, …).
                // Do NOT set recordedAny — this op was never persisted; skipping
                // the trailing push avoids a spurious badge-clear on a lost write.
                // The local mutation already committed, so this op will never reach
                // the server (silent local/remote drift) until the row is re-edited
                // — log it so the maintainer can spot the divergence in Console.
                Self.logger.error(
                    "outbox enqueue failed for \(op.entityType.rawValue, privacy: .public)/\(op.entityId, privacy: .public): \(error.localizedDescription, privacy: .public) — local write will not sync until re-edited"
                )
            }
        }

        // Fire-and-forget the shared finish so the mutating store never blocks on
        // the network. Gated on `recordedAny`: if every enqueue threw, nothing was
        // persisted, so skip the finish — pushing would spuriously clear the 待同步
        // badge for a write that never landed.
        guard recordedAny else { return }
        Task { @MainActor in await self.finishPush() }
    }

    /// Finishing sequence for a writer that recorded its outbox op OUT OF BAND —
    /// the widget toggle drain via `ShoppingToggleService`, which must stay
    /// coordinator-free so `SyncCoordinator` / Supabase never link into the widget
    /// process. The enqueue is allowed to bypass `SyncWriter`; the FINISH is not.
    /// Runs the SAME push + bump the enqueue path runs (so a finishing step can't
    /// be dropped — the `dabcbd4` bug), preceded by the optional cross-instance
    /// refresh pulse (so other live store instances reload — the `c0defc8` bug).
    ///
    /// `didWrite` is the caller's assertion that a real local change landed: the
    /// drain gates on a flipped row, not on `recordedAny`, because the enqueue
    /// happened across the bypass where this seam can't observe it. A local-only
    /// flip (no household) enqueued nothing, so it refreshes the foreground list
    /// but has nothing to push and no badge to converge.
    func finishDirectOutboxWrite(didWrite: Bool, refresh: (@MainActor () -> Void)? = nil) async {
        guard didWrite else { return }
        refresh?()
        guard !session.selectedHouseholdId.isEmpty else { return }
        await finishPush()
    }

    /// The shared finish core: one coalesced push, THEN the 待同步 bump (ordered —
    /// bump after the push, regardless of its outcome, so the badge re-reads a
    /// converged outbox and stays lit if ops remain). `coordinator` may be nil
    /// (local-only-with-household / no client): the push no-ops but the bump still
    /// fires so badges re-read reality. Both the fire-and-forget enqueue tail and
    /// the awaited direct-outbox entry funnel through HERE, so push + bump can
    /// never diverge between the two write paths.
    private func finishPush() async {
        await coordinator?.pushPending()
        session.bumpPendingSyncRevision()
    }
}
