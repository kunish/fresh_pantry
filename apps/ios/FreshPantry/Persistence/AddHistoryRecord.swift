import Foundation
import SwiftData

/// Frequency-memory payload backing `FrequentItem` (Drift `add_history_entries`
/// payload `{count, category, storage, unit}`). NOT synced; no household scope.
struct AddHistoryEntry: Equatable, Sendable, Codable {
    var count: Int
    var category: String
    var storage: String
    var unit: String

    init(count: Int, category: String, storage: String, unit: String) {
        self.count = count
        self.category = category
        self.storage = storage
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey { case count, category, storage, unit }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(count, forKey: .count)
        try c.encode(category, forKey: .category)
        try c.encode(storage, forKey: .storage)
        try c.encode(unit, forKey: .unit)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `count` tolerant of a bare-number historical shape is handled by the
        // repo; here it is a present int (default 1 for resilience).
        count = c.decodeIntIfPresent(forKey: .count) ?? 1
        category = c.decodeLenientIfPresent(String.self, forKey: .category) ?? ""
        storage = c.decodeLenientIfPresent(String.self, forKey: .storage) ?? ""
        unit = c.decodeLenientIfPresent(String.self, forKey: .unit) ?? ""
    }
}

/// SwiftData row for the add-history table. `name` IS the natural key (unique).
@Model
final class AddHistoryRecord {
    @Attribute(.unique) var name: String = ""
    var payloadJSON: String = ""

    init(name: String, entry: AddHistoryEntry) {
        self.name = name
        payloadJSON = (try? DomainJSON.encodeToString(entry)) ?? ""
    }

    func apply(_ entry: AddHistoryEntry) {
        payloadJSON = (try? DomainJSON.encodeToString(entry)) ?? payloadJSON
    }

    func entry() throws -> AddHistoryEntry {
        try DomainJSON.decode(AddHistoryEntry.self, from: payloadJSON)
    }
}
