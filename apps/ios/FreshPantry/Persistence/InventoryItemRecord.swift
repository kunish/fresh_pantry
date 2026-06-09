import Foundation
import SwiftData

/// SwiftData row for the inventory table (Drift `inventory_items`).
///
/// The domain `Ingredient` (stored as `payloadJSON`) is the SOURCE OF TRUTH; the
/// scalar columns are projections kept in lockstep via `apply(_:)`. NOTE: per
/// the storage blueprint, `id` is NOT `@Attribute(.unique)` — blank ids
/// legitimately repeat for local-only rows. Non-empty-id uniqueness within a
/// household is enforced in code at upsert time (mirrors the partial index).
@Model
final class InventoryItemRecord {
    var id: String = ""
    var householdID: String = ""
    var name: String = ""
    var storageArea: String?
    var expiryDate: Date?
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, ingredient: Ingredient) {
        self.householdID = householdID
        apply(ingredient)
    }

    /// Derives every column from the domain struct (single source of truth).
    func apply(_ ingredient: Ingredient) {
        id = ingredient.id
        name = ingredient.name
        storageArea = ingredient.storage.rawValue
        expiryDate = ingredient.expiryDate
        remoteVersion = ingredient.remoteVersion
        deletedAt = ingredient.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(ingredient)) ?? payloadJSON
    }

    /// Decodes the domain struct from the payload (the only field read back).
    func ingredient() throws -> Ingredient {
        try DomainJSON.decode(Ingredient.self, from: payloadJSON)
    }
}
