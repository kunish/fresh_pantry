import Foundation

/// A queued sync mutation (outbox row). Ported from `lib/sync/sync_operation.dart`.
/// `patch` is an opaque JSON object preserved byte-faithfully via `JSONValue`.
///
/// `createdAt` is serialized ISO8601 (the wire format), matching the Flutter
/// `toJson` — the Drift column-unit difference (epoch seconds) is purely internal.
struct SyncOperation: Equatable, Sendable, Codable {
    var id: String
    var householdId: String
    var entityType: SyncEntityType
    var entityId: String
    var operation: SyncOperationType
    var patch: [String: JSONValue]
    var baseVersion: Int?
    var clientId: String
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: String,
        householdId: String,
        entityType: SyncEntityType,
        entityId: String,
        operation: SyncOperationType,
        patch: [String: JSONValue],
        baseVersion: Int? = nil,
        clientId: String,
        createdAt: Date,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.patch = patch
        self.baseVersion = baseVersion
        self.clientId = clientId
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id, householdId, entityType, entityId, operation, patch
        case baseVersion, clientId, createdAt, attemptCount, lastError
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(entityType.rawValue, forKey: .entityType)
        try c.encode(entityId, forKey: .entityId)
        try c.encode(operation.rawValue, forKey: .operation)
        try c.encode(patch, forKey: .patch)
        try c.encodeAlways(baseVersion, forKey: .baseVersion)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(JSONDate.iso8601(createdAt), forKey: .createdAt)
        try c.encode(attemptCount, forKey: .attemptCount)
        try c.encodeAlways(lastError, forKey: .lastError)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let id = SyncOperation.requiredString(c, .id),
            let householdId = SyncOperation.requiredString(c, .householdId),
            let entityTypeRaw = SyncOperation.requiredString(c, .entityType),
            let entityType = SyncEntityType(rawValue: entityTypeRaw),
            let entityId = SyncOperation.requiredString(c, .entityId),
            let operationRaw = SyncOperation.requiredString(c, .operation),
            let operation = SyncOperationType(rawValue: operationRaw),
            let clientId = SyncOperation.requiredString(c, .clientId),
            let createdRaw = SyncOperation.requiredString(c, .createdAt),
            let createdAt = JSONDate.parse(createdRaw),
            let patch = c.decodeLenientIfPresent([String: JSONValue].self, forKey: .patch)
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid sync operation")
            )
        }
        self.init(
            id: id,
            householdId: householdId,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            patch: patch,
            baseVersion: c.decodeIntIfPresent(forKey: .baseVersion),
            clientId: clientId,
            createdAt: createdAt,
            attemptCount: c.decodeIntIfPresent(forKey: .attemptCount) ?? 0,
            lastError: c.decodeLenientIfPresent(String.self, forKey: .lastError)
        )
    }

    private static func requiredString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        guard let value = c.decodeLenientIfPresent(String.self, forKey: key),
              !value.trimmed.isEmpty
        else { return nil }
        return value
    }
}
