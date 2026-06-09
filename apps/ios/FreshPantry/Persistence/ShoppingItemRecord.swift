import Foundation
import SwiftData

/// SwiftData row for the shopping table (Drift `shopping_items`).
/// `id` IS the natural key here (unique).
@Model
final class ShoppingItemRecord {
    @Attribute(.unique) var id: String = ""
    var householdID: String = ""
    var name: String = ""
    var isChecked: Bool = false
    var remoteVersion: Int = 0
    var deletedAt: Date?
    var payloadJSON: String = ""

    init(householdID: String, item: ShoppingItem) {
        self.householdID = householdID
        apply(item)
    }

    func apply(_ item: ShoppingItem) {
        id = item.id
        name = item.name
        isChecked = item.isChecked
        remoteVersion = item.remoteVersion
        deletedAt = item.deletedAt
        payloadJSON = (try? DomainJSON.encodeToString(item)) ?? payloadJSON
    }

    func item() throws -> ShoppingItem {
        try DomainJSON.decode(ShoppingItem.self, from: payloadJSON)
    }
}
