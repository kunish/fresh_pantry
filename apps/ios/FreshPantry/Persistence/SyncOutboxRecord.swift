import Foundation
import SwiftData

/// SwiftData row for the sync outbox (Drift `sync_outbox`).
/// `id` IS the natural key (unique). The full `SyncOperation.toJson()` is the
/// source of truth in `payloadJSON`; columns are projections for query/ordering.
@Model
final class SyncOutboxRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    var entityType: String = ""
    var entityID: String = ""
    var operation: String = ""
    var baseVersion: Int?
    var clientID: String = ""
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var payloadJSON: String = ""

    init(operation op: SyncOperation) {
        apply(op)
    }

    func apply(_ op: SyncOperation) {
        id = op.id
        householdID = op.householdId
        entityType = op.entityType.rawValue
        entityID = op.entityId
        operation = op.operation.rawValue
        baseVersion = op.baseVersion
        clientID = op.clientId
        createdAt = op.createdAt
        payloadJSON = (try? DomainJSON.encodeToString(op)) ?? payloadJSON
    }

    func syncOperation() throws -> SyncOperation {
        try DomainJSON.decode(SyncOperation.self, from: payloadJSON)
    }
}
