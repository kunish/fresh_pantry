import SwiftUI

/// Per-category color pair: `tint` (avatar background / soft fill) and `ink`
/// (stroke / text / icon). Ported from Flutter `FkCategoryPalette`; ids match
/// the design source (`data.jsx::FK_CATEGORIES`).
struct FkCategoryColors: Sendable {
    let tint: Color
    let ink: Color
}

enum FkCategoryPalette {
    static let veg = FkCategoryColors(tint: Color(hex: 0xE8F3E1), ink: Color(hex: 0x4F7A3A))
    static let fruit = FkCategoryColors(tint: Color(hex: 0xFBE0D7), ink: Color(hex: 0xB5523A))
    static let meat = FkCategoryColors(tint: Color(hex: 0xFDD6CE), ink: Color(hex: 0xA8442C))
    static let sea = FkCategoryColors(tint: Color(hex: 0xD6EBF2), ink: Color(hex: 0x3F7691))
    static let dairy = FkCategoryColors(tint: Color(hex: 0xE5ECFA), ink: Color(hex: 0x3F60B5))
    static let drink = FkCategoryColors(tint: Color(hex: 0xE2EAF5), ink: Color(hex: 0x4A5E91))
    static let sauce = FkCategoryColors(tint: Color(hex: 0xF0EBE3), ink: Color(hex: 0x7A6748))
    static let grain = FkCategoryColors(tint: Color(hex: 0xFFF3D6), ink: Color(hex: 0x9B7A2A))
    static let snack = FkCategoryColors(tint: Color(hex: 0xFBE3CE), ink: Color(hex: 0xA85F2C))

    static let all: [String: FkCategoryColors] = [
        "veg": veg, "fruit": fruit, "meat": meat, "sea": sea, "dairy": dairy,
        "drink": drink, "sauce": sauce, "grain": grain, "snack": snack,
    ]

    /// Falls back to `grain` for unknown ids (matches Flutter behavior).
    static func of(_ categoryId: String) -> FkCategoryColors {
        all[categoryId] ?? grain
    }
}
