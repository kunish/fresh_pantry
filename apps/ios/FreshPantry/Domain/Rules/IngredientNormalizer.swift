import Foundation

/// Inventory ingredient normalization ported from
/// `lib/utils/ingredient_normalizer.dart`. Applied per-row on inventory load so
/// category + freshness/expiry labels stay current.
enum IngredientNormalizer {
    /// Canonicalizes the category (returns the item unchanged if already canonical).
    static func normalizeCategory(_ item: Ingredient) -> Ingredient {
        let category = FoodCategories.normalize(item.category)
        if category == item.category { return item }
        return item.copyWith(category: category)
    }

    /// Resolves the effective shelf life: saved value > knowledge-base default >
    /// derived from addedAt..expiry. nil when none is positive.
    static func shelfLifeDays(_ item: Ingredient) -> Int? {
        guard let expiryDate = item.expiryDate else { return nil }
        if let saved = item.shelfLifeDays, saved > 0 { return saved }
        if let knowledge = FoodKnowledge.lookup(item.name)?.shelfLifeDays, knowledge > 0 {
            return knowledge
        }
        guard let addedAt = item.addedAt else { return nil }
        let days = ExpiryCalculator.calendarDaysBetween(addedAt, expiryDate)
        return days > 0 ? days : nil
    }

    /// Recomputes freshnessPercent/state/expiryLabel from the expiry date.
    static func refreshFreshness(_ item: Ingredient, now: Date = Date()) -> Ingredient {
        guard let expiryDate = item.expiryDate else { return item }
        guard let shelfLife = shelfLifeDays(item) else {
            return item.copyWith(expiryLabel: ExpiryCalculator.expiryLabelFor(expiryDate, now: now))
        }
        let freshness = ExpiryCalculator.expiryFreshness(
            expiryDate: expiryDate,
            totalShelfLifeDays: shelfLife,
            now: now
        )
        return item.copyWith(
            freshnessPercent: freshness,
            state: ExpiryCalculator.freshnessStateForExpiry(
                freshness: freshness,
                expiryDate: expiryDate,
                now: now
            ),
            expiryLabel: ExpiryCalculator.expiryLabelFor(expiryDate, now: now)
        )
    }

    /// The full inventory-load normalization: category + freshness refresh.
    static func normalizeInventoryIngredient(_ item: Ingredient, now: Date = Date()) -> Ingredient {
        refreshFreshness(normalizeCategory(item), now: now)
    }
}
