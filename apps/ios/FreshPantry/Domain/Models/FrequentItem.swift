import Foundation

/// Derived "frequently added item" with remembered defaults. Pure view-model
/// (no sync). Full value equality so the derived list compares by content.
/// Backed at persistence by AddHistory rows ({count,category,storage,unit}).
struct FrequentItem: Equatable, Sendable {
    var name: String
    var category: String
    var storage: IconType
    var unit: String
    var shelfLifeDays: Int?
    var count: Int

    init(
        name: String,
        category: String,
        storage: IconType,
        unit: String,
        shelfLifeDays: Int? = nil,
        count: Int
    ) {
        self.name = name
        self.category = category
        self.storage = storage
        self.unit = unit
        self.shelfLifeDays = shelfLifeDays
        self.count = count
    }
}
