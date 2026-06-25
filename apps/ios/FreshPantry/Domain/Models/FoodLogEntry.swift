import Foundation

/// Append-only food-departure log (consumed vs wasted) — truth source for
/// waste-reduction stats. Identity (Hashable/Equatable) is by `id` ONLY.
///
/// `loggedAt` is normalized to UTC (stored UTC, stats convert to local) and
/// serialized as ISO8601. `fromJson` THROWS on missing/unparseable date so the
/// repo can catch+skip a dirty row. Quantity is intentionally NOT logged.
struct FoodLogEntry: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var category: String
    var outcome: FoodLogOutcome
    /// Event timestamp, normalized to UTC at construction. (Foundation `Date`
    /// is an absolute instant, so no conversion is needed; the instant matches.)
    var loggedAt: Date
    var wasExpiring: Bool
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    var isConsumed: Bool { outcome == .consumed }
    var isWasted: Bool { outcome == .wasted }
    /// Rescued a perishable that was already expiring (positive waste-reduction).
    var rescuedExpiring: Bool { isConsumed && wasExpiring }

    init(
        id: String,
        name: String,
        category: String = FoodCategories.other,
        outcome: FoodLogOutcome,
        loggedAt: Date,
        wasExpiring: Bool = false,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.outcome = outcome
        self.loggedAt = loggedAt
        self.wasExpiring = wasExpiring
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    /// Canonical id format: lowercase UUID (synced to a Supabase `uuid` PK column).
    static func newId() -> String { UUID().uuidString.lowercased() }

    static func == (lhs: FoodLogEntry, rhs: FoodLogEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, outcome, loggedAt, wasExpiring
        case remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(outcome.rawValue, forKey: .outcome)
        // loggedAt always present (non-optional) — encoded as UTC ISO8601.
        try c.encode(JSONDate.iso8601(loggedAt), forKey: .loggedAt)
        try c.encode(wasExpiring, forKey: .wasExpiring)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawLoggedAt = c.decodeLenientIfPresent(String.self, forKey: .loggedAt)
        guard let loggedAt = JSONDate.fromJSONValue(rawLoggedAt) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: c.codingPath,
                    debugDescription: "FoodLogEntry.loggedAt missing or unparseable"
                )
            )
        }
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            name: c.decodeLenientIfPresent(String.self, forKey: .name) ?? "",
            category: c.decodeLenientIfPresent(String.self, forKey: .category) ?? FoodCategories.other,
            outcome: FoodLogOutcome.fromName(c.decodeLenientIfPresent(String.self, forKey: .outcome)),
            loggedAt: loggedAt,
            wasExpiring: c.decodeLenientIfPresent(Bool.self, forKey: .wasExpiring) ?? false,
            remoteVersion: c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0,
            clientUpdatedAt: c.decodeISODateIfPresent(forKey: .clientUpdatedAt),
            deletedAt: c.decodeISODateIfPresent(forKey: .deletedAt)
        )
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        category: String? = nil,
        outcome: FoodLogOutcome? = nil,
        loggedAt: Date? = nil,
        wasExpiring: Bool? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> FoodLogEntry {
        FoodLogEntry(
            id: id ?? self.id,
            name: name ?? self.name,
            category: category ?? self.category,
            outcome: outcome ?? self.outcome,
            loggedAt: loggedAt ?? self.loggedAt,
            wasExpiring: wasExpiring ?? self.wasExpiring,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}
