import Foundation

/// Static preset values surfaced in the custom-recipe authoring form. Ported from
/// `lib/data/recipe_presets.dart`. These are recipe-domain presets (cuisine
/// categories / cooking-time chips / ingredient units) and are deliberately
/// SEPARATE from `FoodCategories` (the inventory perishability taxonomy) — a
/// recipe's category is a freeform cuisine label, not one of the five inventory
/// buckets.
enum RecipePresets {
    /// Cuisine category presets. A custom value the user typed is appended ahead
    /// of these by the form; the trailing "其他" sentinel opens a freeform entry.
    static let categories = ["家常", "川菜", "粤菜", "西式", "烘焙", "汤羹"]

    /// Cooking-time presets (minutes). The last value (120) renders as "120+" but
    /// still writes 120 on tap.
    static let cookingMinutes = [15, 30, 45, 60, 90, 120]

    /// Ingredient unit presets. A "自定义…" entry is appended by the picker.
    static let units = ["g", "ml", "kg", "个", "把", "根", "颗", "片", "杯", "勺", "适量"]
}
