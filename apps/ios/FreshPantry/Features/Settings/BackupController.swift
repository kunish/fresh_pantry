import Foundation

/// Orchestrates backup export/import against the live, repository-backed stores.
///
/// This is the ViewModel-level seam the Settings 备份 screen calls: it reads the
/// real source of truth on export and writes it back on import, leaving the View
/// to map decode errors to dialogs and confirm the destructive action. The pure
/// (de)serialization lives in `BackupService`.
@MainActor
final class BackupController {
    private let inventory: InventoryRepository
    private let shopping: ShoppingRepository
    private let customRecipe: CustomRecipeRepository
    private let mealPlan: MealPlanRepository
    private let aiSettings: AiSettingsStore
    private let householdID: String

    init(
        inventory: InventoryRepository,
        shopping: ShoppingRepository,
        customRecipe: CustomRecipeRepository,
        mealPlan: MealPlanRepository,
        aiSettings: AiSettingsStore,
        householdID: String
    ) {
        self.inventory = inventory
        self.shopping = shopping
        self.customRecipe = customRecipe
        self.mealPlan = mealPlan
        self.aiSettings = aiSettings
        self.householdID = householdID
    }

    /// Reads the live persisted state (the source of truth) and serializes it to
    /// a JSON blob. The View wraps the returned string into a file for sharing.
    ///
    /// `aiSettings` is included only when configured, mirroring the Flutter
    /// controller (an empty/unconfigured config has nothing worth round-tripping).
    func exportBackup() async throws -> String {
        let settings = aiSettings.settings
        let data = BackupData(
            inventory: try await inventory.loadAllFor(householdID),
            addHistory: try await inventory.loadHistory(),
            shopping: try await shopping.loadAllFor(householdID),
            customRecipes: try await customRecipe.loadAllFor(householdID),
            mealPlan: try await mealPlan.loadAllFor(householdID),
            aiSettings: settings.isConfigured ? settings : nil
        )
        return BackupService.encode(data)
    }

    /// Decodes `string` (full structural validation — invariant #8) and only THEN
    /// writes each scope, so a malformed import throws BEFORE any write and never
    /// partially overwrites live data. Any persistence failure propagates out so
    /// the caller surfaces it instead of falsely reporting a completed restore.
    func importBackup(_ string: String) async throws {
        let data = try BackupService.decode(string)

        try await inventory.saveItems(householdID, data.inventory)
        try await inventory.saveHistory(data.addHistory)
        try await shopping.saveItems(householdID, data.shopping)
        try await customRecipe.saveRecipes(householdID, data.customRecipes)
        try await mealPlan.saveEntries(householdID, data.mealPlan)

        if let aiSettings = data.aiSettings {
            self.aiSettings.save(aiSettings)
        }
    }
}
