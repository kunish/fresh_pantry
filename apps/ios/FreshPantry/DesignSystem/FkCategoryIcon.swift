import SwiftUI

/// Maps the canonical 5 food categories onto the 9 design-system palette ids and
/// their SF Symbol glyphs. Ported from Flutter `fkCategoryIdFor` + the cartoon
/// `CatIcon` set (collapsed to SF Symbols for this slice — the hand-drawn vector
/// set is a later enhancement, see widgets.md invariant #8).
enum FkCategoryIcon {
    /// Category → palette id. Mirrors `fkCategoryIdFor`: dairyAndEggs→dairy,
    /// freshProduce→veg, meatAndSeafood→meat, herbsAndSpices→sauce, else→grain.
    static func paletteId(for category: String?) -> String {
        switch FoodCategories.normalize(category) {
        case FoodCategories.dairyAndEggs: return "dairy"
        case FoodCategories.freshProduce: return "veg"
        case FoodCategories.meatAndSeafood: return "meat"
        case FoodCategories.herbsAndSpices: return "sauce"
        default: return "grain"
        }
    }

    /// Palette colors for a category (default `grain`).
    static func palette(for category: String?) -> FkCategoryColors {
        FkCategoryPalette.of(paletteId(for: category))
    }

    /// SF Symbol standing in for the cartoon category glyph.
    static func symbol(for category: String?) -> String {
        switch paletteId(for: category) {
        case "dairy": return "takeoutbag.and.cup.and.straw.fill"
        case "veg": return "carrot.fill"
        case "meat": return "fish.fill"
        case "sauce": return "leaf.fill"
        default: return "basket.fill"
        }
    }
}

extension IconType {
    /// SF Symbol for a storage zone (cartoon `ZoneIcon` stand-in for this slice).
    var sfSymbol: String {
        switch self {
        case .fridge: return "refrigerator.fill"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet.fill"
        }
    }
}
