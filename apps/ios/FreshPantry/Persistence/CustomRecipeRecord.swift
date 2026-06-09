import Foundation
import SwiftData

/// SwiftData row for the custom-recipes table (Drift `custom_recipes`).
/// `id` IS the natural key here (unique).
@Model
final class CustomRecipeRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    var name: String = ""
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, recipe: Recipe) {
        self.householdID = householdID
        apply(recipe)
    }

    func apply(_ recipe: Recipe) {
        id = recipe.id
        name = recipe.name
        remoteVersion = recipe.remoteVersion
        deletedAt = recipe.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(recipe)) ?? payloadJSON
    }

    func recipe() throws -> Recipe {
        try DomainJSON.decode(Recipe.self, from: payloadJSON)
    }
}
