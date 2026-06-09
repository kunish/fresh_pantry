import Foundation

/// Derived per-area summary view-model (NOT a persisted entity, no sync triplet).
/// `name` is the business key but equality covers all four fields.
struct StorageArea: Equatable, Sendable, Codable {
    var name: String
    var icon: IconType
    var itemCount: Int
    var capacityPercent: Double

    init(name: String, icon: IconType, itemCount: Int, capacityPercent: Double) {
        self.name = name
        self.icon = icon
        self.itemCount = itemCount
        self.capacityPercent = capacityPercent
    }

    func copyWith(
        name: String? = nil,
        icon: IconType? = nil,
        itemCount: Int? = nil,
        capacityPercent: Double? = nil
    ) -> StorageArea {
        StorageArea(
            name: name ?? self.name,
            icon: icon ?? self.icon,
            itemCount: itemCount ?? self.itemCount,
            capacityPercent: capacityPercent ?? self.capacityPercent
        )
    }

    private enum CodingKeys: String, CodingKey {
        case name, icon, itemCount, capacityPercent
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(icon.rawValue, forKey: .icon)
        try c.encode(itemCount, forKey: .itemCount)
        try c.encode(capacityPercent, forKey: .capacityPercent)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.decodeLenientIfPresent(String.self, forKey: .name) ?? ""
        icon = IconType.fromName(c.decodeLenientIfPresent(String.self, forKey: .icon))
        itemCount = c.decodeIntIfPresent(forKey: .itemCount) ?? 0
        capacityPercent = c.decodeDoubleIfPresent(forKey: .capacityPercent) ?? 0.0
    }
}
