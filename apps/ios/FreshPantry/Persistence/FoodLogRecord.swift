import Foundation
import SwiftData

/// SwiftData row for the food-log table (Drift `food_log_entries`).
/// `id` IS the natural key here (unique). `loggedAt` is indexed for the bounded
/// recent-window query.
@Model
final class FoodLogRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    var name: String = ""
    var loggedAt: Date?
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, entry: FoodLogEntry) {
        self.householdID = householdID
        apply(entry)
    }

    func apply(_ entry: FoodLogEntry) {
        id = entry.id
        name = entry.name
        loggedAt = entry.loggedAt
        remoteVersion = entry.remoteVersion
        deletedAt = entry.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(entry)) ?? payloadJSON
    }

    func entry() throws -> FoodLogEntry {
        try DomainJSON.decode(FoodLogEntry.self, from: payloadJSON)
    }
}
