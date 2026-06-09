import Foundation

/// Guards local rows from leaking across households during upload/merge.
///
/// Ported from the `_LocalUploadScope` helper in
/// `lib/sync/household_content_sync_coordinator.dart`. A local row that already
/// has a pending outbox op targeting a *different* household must not be
/// uploaded into — or merged into the view of — the current household. The map
/// records, per entity type and entity id, the set of households with a pending
/// op for that row; `allows` lets a row through only when no pending op claims
/// it for another household.
struct LocalUploadScope: Sendable {
    private let householdID: String
    private let pendingHouseholdsByEntity: [SyncEntityType: [String: Set<String>]]

    init(householdID: String, pendingOps: [SyncOperation]) {
        self.householdID = householdID
        self.pendingHouseholdsByEntity = Self.pendingHouseholdsByEntityType(pendingOps)
    }

    /// True when `entityID` may participate in the current household's
    /// upload/merge: rejected when empty; allowed when no pending op targets the
    /// row, or when at least one pending op targets it for *this* household.
    func allows(_ entityType: SyncEntityType, _ entityID: String) -> Bool {
        if entityID.isEmpty { return false }
        let pendingHouseholds = pendingHouseholdsByEntity[entityType]?[entityID]
        guard let pendingHouseholds, !pendingHouseholds.isEmpty else { return true }
        return pendingHouseholds.contains(householdID)
    }

    /// Indexes pending ops as `entityType → entityId → {householdId}`. Mirrors
    /// the Dart `_pendingHouseholdsByEntityType`: ops with a blank (trimmed)
    /// entity id or household id are skipped, so they neither block nor allow.
    private static func pendingHouseholdsByEntityType(
        _ operations: [SyncOperation]
    ) -> [SyncEntityType: [String: Set<String>]] {
        var result: [SyncEntityType: [String: Set<String>]] = [:]
        for operation in operations {
            let entityID = operation.entityId.trimmed
            let householdID = operation.householdId.trimmed
            if entityID.isEmpty || householdID.isEmpty { continue }
            result[operation.entityType, default: [:]][entityID, default: []].insert(householdID)
        }
        return result
    }
}
