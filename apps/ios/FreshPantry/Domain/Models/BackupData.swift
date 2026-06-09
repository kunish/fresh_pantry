import Foundation

/// The full set of user data a backup captures, as typed domain models.
///
/// This is the boundary between the pure codec (`BackupService`) and the
/// orchestration that reads/writes the live stores (`BackupController`). Cache
/// data (e.g. food-details lookups) is intentionally excluded — it regenerates
/// and would bloat the blob (parity invariant #8).
struct BackupData: Equatable, Sendable {
    var inventory: [Ingredient]

    /// Add-history frequency memory kept as its typed map shape (name -> payload);
    /// it round-trips verbatim — the codec never reshapes it.
    var addHistory: [String: AddHistoryEntry]
    var shopping: [ShoppingItem]
    var customRecipes: [Recipe]
    var mealPlan: [MealPlanEntry]
    var aiSettings: AiSettings?

    init(
        inventory: [Ingredient],
        addHistory: [String: AddHistoryEntry],
        shopping: [ShoppingItem],
        customRecipes: [Recipe],
        mealPlan: [MealPlanEntry],
        aiSettings: AiSettings? = nil
    ) {
        self.inventory = inventory
        self.addHistory = addHistory
        self.shopping = shopping
        self.customRecipes = customRecipes
        self.mealPlan = mealPlan
        self.aiSettings = aiSettings
    }
}
