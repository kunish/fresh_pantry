import Foundation
import SwiftData

/// SwiftData row for the meal-plan table (Drift `meal_plan_entries`).
/// `id` IS the natural key here (unique). The `name` column holds `recipeName`.
@Model
final class MealPlanRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    /// Holds `recipeName` (matches the Drift column semantics).
    var name: String = ""
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, entry: MealPlanEntry) {
        self.householdID = householdID
        apply(entry)
    }

    func apply(_ entry: MealPlanEntry) {
        id = entry.id
        name = entry.recipeName
        remoteVersion = entry.remoteVersion
        deletedAt = entry.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(entry)) ?? payloadJSON
    }

    func entry() throws -> MealPlanEntry {
        try DomainJSON.decode(MealPlanEntry.self, from: payloadJSON)
    }
}
