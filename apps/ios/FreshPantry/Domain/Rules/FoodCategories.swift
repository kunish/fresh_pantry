import Foundation

/// Category canonicalization + perishability source. Ported VERBATIM from
/// `lib/data/food_categories.dart` (alias map + perishable set must match for
/// sync parity).
enum FoodCategories {
    static let dairyAndEggs = "乳品蛋类"
    static let freshProduce = "果蔬生鲜"
    static let meatAndSeafood = "肉类海鲜"
    static let herbsAndSpices = "香料草本"
    static let other = "其他"

    static let removedPantryStaples = "食品柜常备"

    /// Legacy/synonym Chinese labels → 5 canonical. Unmapped non-empty → other.
    private static let aliases: [String: String] = [
        dairyAndEggs: dairyAndEggs,
        "乳制品与蛋类": dairyAndEggs,
        "乳制品与干货": dairyAndEggs,
        "乳制品": dairyAndEggs,
        "乳品": dairyAndEggs,
        "蛋类": dairyAndEggs,
        "蛋": dairyAndEggs,
        freshProduce: freshProduce,
        "新鲜蔬果": freshProduce,
        "蔬菜": freshProduce,
        "水果": freshProduce,
        "果蔬": freshProduce,
        "生鲜": freshProduce,
        meatAndSeafood: meatAndSeafood,
        "肉类与海鲜": meatAndSeafood,
        "肉类": meatAndSeafood,
        "海鲜": meatAndSeafood,
        "蛋白质": meatAndSeafood,
        herbsAndSpices: herbsAndSpices,
        "香料与草本": herbsAndSpices,
        "香料": herbsAndSpices,
        "草本": herbsAndSpices,
        "调味品": herbsAndSpices,
        "调味料": herbsAndSpices,
        other: other,
        removedPantryStaples: other,
        "谷物": other,
        "主食": other,
        "干货": other,
    ]

    static let values = [
        dairyAndEggs,
        freshProduce,
        meatAndSeafood,
        herbsAndSpices,
        other,
    ]

    /// nil/empty → nil; mapped alias or `other` for any unmapped non-empty value.
    static func normalize(_ category: String?) -> String? {
        guard let trimmed = category?.trimmed, !trimmed.isEmpty else { return nil }
        return aliases[trimmed] ?? other
    }

    static func dropdownValue(_ category: String?) -> String {
        normalize(category) ?? other
    }

    /// Perishable categories track each intake as a new batch (per ADR-0001).
    private static let perishable: Set<String> = [
        freshProduce,
        meatAndSeafood,
        dairyAndEggs,
    ]

    static func isPerishable(_ category: String?) -> Bool {
        guard let normalized = normalize(category) else { return false }
        return perishable.contains(normalized)
    }
}
