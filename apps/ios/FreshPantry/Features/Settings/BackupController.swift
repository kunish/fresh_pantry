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
    private let foodLog: FoodLogRepository
    private let shopping: ShoppingRepository
    private let customRecipe: CustomRecipeRepository
    private let mealPlan: MealPlanRepository
    private let aiSettings: AiSettingsStore
    private let favorites: FavoritesStore
    private let dietaryPreferences: DietaryPreferencesStore
    private let dietPreference: DietPreferenceStore
    private let reminderSettings: ReminderSettingsStore
    private let syncWriter: SyncWriter
    private let householdID: String

    init(
        inventory: InventoryRepository,
        foodLog: FoodLogRepository,
        shopping: ShoppingRepository,
        customRecipe: CustomRecipeRepository,
        mealPlan: MealPlanRepository,
        aiSettings: AiSettingsStore,
        favorites: FavoritesStore,
        dietaryPreferences: DietaryPreferencesStore,
        dietPreference: DietPreferenceStore,
        reminderSettings: ReminderSettingsStore,
        syncWriter: SyncWriter,
        householdID: String
    ) {
        self.inventory = inventory
        self.foodLog = foodLog
        self.shopping = shopping
        self.customRecipe = customRecipe
        self.mealPlan = mealPlan
        self.aiSettings = aiSettings
        self.favorites = favorites
        self.dietaryPreferences = dietaryPreferences
        self.dietPreference = dietPreference
        self.reminderSettings = reminderSettings
        self.syncWriter = syncWriter
        self.householdID = householdID
    }

    /// Reads the live persisted state (the source of truth) and serializes it to
    /// a JSON blob. The View wraps the returned string into a file for sharing.
    ///
    /// `aiSettings` is included only when configured, mirroring the Flutter
    /// controller (an empty/unconfigured config has nothing worth round-tripping).
    /// The iOS-only scopes are ALWAYS written — even when empty — so a restore
    /// can tell "backed up empty" from "not in this backup" (see `BackupArchive`).
    func exportBackup() async throws -> String {
        let settings = aiSettings.settings
        let archive = BackupArchive(
            data: BackupData(
                inventory: try await inventory.loadAllFor(householdID),
                addHistory: try await inventory.loadHistory(),
                shopping: try await shopping.loadAllFor(householdID),
                customRecipes: try await customRecipe.loadAllFor(householdID),
                mealPlan: try await mealPlan.loadAllFor(householdID),
                aiSettings: settings.isConfigured ? settings : nil
            ),
            foodLog: try await foodLog.loadAllFor(householdID),
            favorites: favorites.favoriteIDs.sorted(),
            dietaryExclusions: dietaryPreferences.sortedKeywords,
            dietPreferences: dietPreference.sortedSelected,
            reminderSettings: reminderSettings.settings
        )
        return BackupService.encode(archive)
    }

    /// Import-time persistence failure the repositories don't already throw
    /// for: `AiSettingsStore.save` reports a rejected Keychain write via its
    /// Bool result, so the importer maps `false` to this typed error.
    enum ImportError: Error, Equatable {
        case aiSettingsPersistFailed
    }

    /// Decodes `string` (full structural validation — invariant #8) and only THEN
    /// writes each scope, so a malformed import throws BEFORE any write and never
    /// partially overwrites live data. Any persistence failure propagates out so
    /// the caller surfaces it instead of falsely reporting a completed restore.
    ///
    /// A nil archive scope (a pre-expansion backup) is SKIPPED, never cleared.
    ///
    /// In a household (`householdID` non-empty) the restored rows must travel the
    /// same outbox pipeline as a manual edit: the realtime merge treats remote as
    /// authoritative and drops synced local rows absent remotely
    /// (`HouseholdMergePolicy`), so a repository-only restore would be silently
    /// rolled back to the pre-import remote state within seconds.
    func importBackup(_ string: String) async throws {
        let archive = try BackupService.decodeArchive(string)
        let data = archive.data

        // Snapshot the synced scopes BEFORE overwriting so the upload can also
        // soft-delete remote rows the restored state no longer contains. A
        // failed snapshot read degrades to "no remote deletes" (the surplus
        // remote rows re-merge in later) instead of failing the restore.
        let previous = await preImportSnapshot()

        try await inventory.saveItems(householdID, data.inventory)
        try await inventory.saveHistory(data.addHistory)
        try await shopping.saveItems(householdID, data.shopping)
        try await customRecipe.saveRecipes(householdID, data.customRecipes)
        try await mealPlan.saveEntries(householdID, data.mealPlan)
        if let entries = archive.foodLog {
            try await foodLog.saveEntries(householdID, entries)
        }

        if let imported = archive.favorites { applyFavorites(imported) }
        if let imported = archive.dietaryExclusions { applyDietaryExclusions(imported) }
        if let imported = archive.dietPreferences { applyDietPreferences(imported) }
        if let imported = archive.reminderSettings { reminderSettings.set(imported) }

        if !householdID.isEmpty {
            await syncWriter.enqueueBatch(Self.importSyncOps(previous: previous, imported: archive))
        }

        // LAST among the scopes (everything above has landed + enqueued, so the
        // synced state stays consistent even when this throws): the Keychain
        // write is the one step that signals failure via a Bool instead of
        // throwing — surface it, or the restore is falsely reported complete
        // while the AI config silently reverts on next launch.
        if let aiSettings = data.aiSettings {
            guard self.aiSettings.save(aiSettings) else {
                throw ImportError.aiSettingsPersistFailed
            }
        }
    }

    // MARK: Import → outbox ops

    /// Pre-import rows of every synced scope, diffed against the archive to
    /// derive the remote soft-deletes.
    struct SyncSnapshot {
        var inventory: [Ingredient] = []
        var shopping: [ShoppingItem] = []
        var customRecipes: [Recipe] = []
        var mealPlan: [MealPlanEntry] = []
        var foodLog: [FoodLogEntry] = []
    }

    /// Maps the "snapshot before → archive after" replacement to the outbox ops
    /// a manual edit of the same rows would have produced: `.create` for a
    /// never-synced row (baseVersion nil), a full-row `.update` for a synced row
    /// (baseVersion = max of the archive row's and the PRE-IMPORT row's
    /// remoteVersion — the gateway 3-way-merges on contention), and a `.delete`
    /// (full-row patch, the gateway derives `deleted_at`) for every pre-import
    /// row the archive no longer contains.
    /// A nil `archive.foodLog` produced no local write, so it produces no ops.
    static func importSyncOps(
        previous: SyncSnapshot,
        imported archive: BackupArchive
    ) -> [SyncWriter.PendingOp] {
        var ops: [SyncWriter.PendingOp] = []
        ops += entityOps(
            .inventoryItem, imported: archive.data.inventory, previous: previous.inventory,
            id: { $0.id }, remoteVersion: { $0.remoteVersion }
        )
        ops += entityOps(
            .shoppingItem, imported: archive.data.shopping, previous: previous.shopping,
            id: { $0.id }, remoteVersion: { $0.remoteVersion }
        )
        ops += entityOps(
            .customRecipe, imported: archive.data.customRecipes, previous: previous.customRecipes,
            id: { $0.id }, remoteVersion: { $0.remoteVersion }
        )
        ops += entityOps(
            .mealPlanEntry, imported: archive.data.mealPlan, previous: previous.mealPlan,
            id: { $0.id }, remoteVersion: { $0.remoteVersion }
        )
        if let entries = archive.foodLog {
            ops += entityOps(
                .foodLogEntry, imported: entries, previous: previous.foodLog,
                id: { $0.id }, remoteVersion: { $0.remoteVersion }
            )
        }
        return ops
    }

    private static func entityOps<Row: Encodable>(
        _ entityType: SyncEntityType,
        imported: [Row],
        previous: [Row],
        id: (Row) -> String,
        remoteVersion: (Row) -> Int
    ) -> [SyncWriter.PendingOp] {
        // Pre-import versions by id: a manual edit bases its op on the EXISTING
        // row's remoteVersion, so the restore must too. An archive row that
        // predates the row's sync (remoteVersion 0) would otherwise produce a
        // create-shaped upsert that the gateway silently ignores
        // (`ignoreDuplicates`) when the remote row exists — and the next merge
        // would roll the restore back. `max` also keeps an archive newer than
        // the snapshot read authoritative.
        let previousVersionById = Dictionary(
            previous.map { (id($0), remoteVersion($0)) },
            uniquingKeysWith: max
        )
        var ops: [SyncWriter.PendingOp] = []
        var importedIds = Set<String>()
        for row in imported {
            let rowId = id(row)
            guard !rowId.trimmed.isEmpty else { continue }
            importedIds.insert(rowId)
            guard let patch = DomainJSON.valueMap(row) else { continue }
            let base = max(remoteVersion(row), previousVersionById[rowId] ?? 0)
            ops.append(SyncWriter.PendingOp(
                entityType: entityType,
                entityId: rowId,
                operation: base > 0 ? .update : .create,
                patch: patch,
                baseVersion: base > 0 ? base : nil
            ))
        }
        for row in previous {
            let rowId = id(row)
            guard !rowId.trimmed.isEmpty, !importedIds.contains(rowId),
                  let patch = DomainJSON.valueMap(row)
            else { continue }
            ops.append(SyncWriter.PendingOp(
                entityType: entityType,
                entityId: rowId,
                operation: .delete,
                patch: patch,
                baseVersion: remoteVersion(row)
            ))
        }
        return ops
    }

    private func preImportSnapshot() async -> SyncSnapshot {
        // Local-only mode never uploads, so the diff base is never read.
        guard !householdID.isEmpty else { return SyncSnapshot() }
        return SyncSnapshot(
            inventory: (try? await inventory.loadAllFor(householdID)) ?? [],
            shopping: (try? await shopping.loadAllFor(householdID)) ?? [],
            customRecipes: (try? await customRecipe.loadAllFor(householdID)) ?? [],
            mealPlan: (try? await mealPlan.loadAllFor(householdID)) ?? [],
            foodLog: (try? await foodLog.loadAllFor(householdID)) ?? []
        )
    }

    // MARK: Preference-scope replacement

    // The KV stores expose no bulk-set API and OWN their input normalization,
    // so each replacement is a diff over the store's own mutations (current
    // sets are snapshotted first — mutating while iterating the live set would
    // skip elements).

    private func applyFavorites(_ imported: [String]) {
        let next = Set(imported.map { $0.trimmed }.filter { !$0.isEmpty })
        let current = favorites.favoriteIDs
        for id in current.subtracting(next) { favorites.toggle(id) }
        for id in next.subtracting(current) { favorites.toggle(id) }
    }

    private func applyDietaryExclusions(_ imported: [String]) {
        let next = Set(imported.map(DietaryPreferencesStore.normalize).filter { !$0.isEmpty })
        let current = dietaryPreferences.keywords
        for keyword in current.subtracting(next) { dietaryPreferences.remove(keyword) }
        for keyword in next.subtracting(current) { dietaryPreferences.add(keyword) }
    }

    private func applyDietPreferences(_ imported: [String]) {
        let next = Set(imported.map(DietPreferenceStore.normalize).filter { !$0.isEmpty })
        let current = dietPreference.selected
        for label in current.subtracting(next) { dietPreference.set(label, on: false) }
        for label in next.subtracting(current) { dietPreference.set(label, on: true) }
    }
}
