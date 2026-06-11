import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Tests for the backup orchestration seam: export reads every scope (incl. the
/// iOS-only ones), import writes them back with absent-scope-skip semantics, and
/// — in a household — mirrors the restored state into the sync outbox exactly
/// like a manual edit would (otherwise the next remote merge would silently roll
/// the restore back). Runs on in-memory SwiftData + isolated UserDefaults suites
/// + a coordinator-less `SyncWriter` (records ops, never pushes).
@MainActor
struct BackupControllerTests {
    // MARK: - Fixture

    private struct Fixture {
        let controller: BackupController
        let inventory: InventoryRepository
        let foodLog: FoodLogRepository
        let favorites: FavoritesStore
        let dietaryPreferences: DietaryPreferencesStore
        let dietPreference: DietPreferenceStore
        let reminderSettings: ReminderSettingsStore
        let outbox: SyncOutboxRepository
        let householdID: String
    }

    private func makeFixture(household: String = "") throws -> Fixture {
        let container = try ModelContainerFactory.makeInMemory()
        let defaults = UserDefaults(suiteName: "test.backupcontroller.\(UUID().uuidString)")!
        let inventory = InventoryRepository(modelContainer: container)
        let foodLog = FoodLogRepository(modelContainer: container)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let session = SyncSession(selectedHouseholdId: household, defaults: defaults)
        let favorites = FavoritesStore(defaults: defaults)
        let dietaryPreferences = DietaryPreferencesStore(defaults: defaults)
        let dietPreference = DietPreferenceStore(defaults: defaults)
        let reminderSettings = ReminderSettingsStore(defaults: defaults)
        let controller = BackupController(
            inventory: inventory,
            foodLog: foodLog,
            shopping: ShoppingRepository(modelContainer: container),
            customRecipe: CustomRecipeRepository(modelContainer: container),
            mealPlan: MealPlanRepository(modelContainer: container),
            aiSettings: AiSettingsStore(secrets: InMemorySecretStore()),
            favorites: favorites,
            dietaryPreferences: dietaryPreferences,
            dietPreference: dietPreference,
            reminderSettings: reminderSettings,
            syncWriter: SyncWriter(outbox: outbox, coordinator: nil, session: session),
            householdID: household
        )
        return Fixture(
            controller: controller,
            inventory: inventory,
            foodLog: foodLog,
            favorites: favorites,
            dietaryPreferences: dietaryPreferences,
            dietPreference: dietPreference,
            reminderSettings: reminderSettings,
            outbox: outbox,
            householdID: household
        )
    }

    private func emptyCore() -> BackupData {
        BackupData(inventory: [], addHistory: [:], shopping: [], customRecipes: [], mealPlan: [])
    }

    private func ingredient(_ id: String, _ name: String, remoteVersion: Int = 0) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "个", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, remoteVersion: remoteVersion
        )
    }

    private func logEntry(_ id: String, _ name: String, remoteVersion: Int = 0) -> FoodLogEntry {
        FoodLogEntry(
            id: id, name: name, outcome: .consumed,
            loggedAt: Date(timeIntervalSince1970: 1_700_000_000),
            remoteVersion: remoteVersion
        )
    }

    // MARK: - Export

    @Test func exportIncludesIOSOnlyScopes() async throws {
        let fixture = try makeFixture()
        try await fixture.foodLog.append("", logEntry("fl-1", "牛奶"))
        fixture.favorites.toggle("r_9")
        fixture.dietaryPreferences.add("辣")
        fixture.dietPreference.set("素食", on: true)
        fixture.reminderSettings.setRemindD7(true)

        let archive = try BackupService.decodeArchive(try await fixture.controller.exportBackup())

        #expect(archive.foodLog?.map(\.id) == ["fl-1"])
        #expect(archive.foodLog?.first?.name == "牛奶")
        #expect(archive.favorites == ["r_9"])
        #expect(archive.dietaryExclusions == ["辣"])
        #expect(archive.dietPreferences == ["素食"])
        #expect(archive.reminderSettings?.remindD7 == true)
    }

    @Test func exportAlwaysWritesIOSOnlyScopesEvenWhenEmpty() async throws {
        // Empty ≠ absent: a fresh install's blob must restore as "clear these",
        // not "skip these" (see `BackupArchive`).
        let fixture = try makeFixture()
        let archive = try BackupService.decodeArchive(try await fixture.controller.exportBackup())
        #expect(archive.foodLog == [])
        #expect(archive.favorites == [])
        #expect(archive.dietaryExclusions == [])
        #expect(archive.dietPreferences == [])
        #expect(archive.reminderSettings == ReminderSettings())
    }

    // MARK: - Import (scope replacement)

    @Test func importRestoresIOSOnlyScopes() async throws {
        let fixture = try makeFixture()
        // Pre-existing state that the restore must REPLACE, not merge.
        fixture.favorites.toggle("r_old")
        fixture.dietPreference.set("快手菜", on: true)
        try await fixture.foodLog.append("", logEntry("fl-old", "旧记录"))

        let blob = BackupService.encode(BackupArchive(
            data: emptyCore(),
            foodLog: [logEntry("fl-new", "面包")],
            favorites: ["r_new"],
            dietaryExclusions: ["花生"],
            dietPreferences: ["低脂"],
            reminderSettings: ReminderSettings(remindD7: true, reminderHour: 8)
        ))
        try await fixture.controller.importBackup(blob)

        #expect(try await fixture.foodLog.loadAllFor("").map(\.id) == ["fl-new"])
        #expect(fixture.favorites.favoriteIDs == ["r_new"])
        #expect(fixture.dietaryPreferences.keywords == ["花生"])
        #expect(fixture.dietPreference.selected == ["低脂"])
        #expect(fixture.reminderSettings.settings.remindD7 == true)
        #expect(fixture.reminderSettings.settings.reminderHour == 8)
    }

    @Test func importLegacyBlobLeavesIOSOnlyScopesUntouched() async throws {
        // A pre-expansion backup carries no optional keys: restoring it must not
        // wipe the food log / preferences it never contained.
        let fixture = try makeFixture()
        try await fixture.inventory.saveItems("", [ingredient("ing-1", "牛奶")])
        try await fixture.foodLog.append("", logEntry("fl-keep", "牛奶"))
        fixture.favorites.toggle("r_keep")
        fixture.reminderSettings.setRemindD7(true)

        try await fixture.controller.importBackup(#"{"version":2,"data":{}}"#)

        // Core scopes ARE replaced (always present in v2)…
        #expect(try await fixture.inventory.loadAllFor("").isEmpty)
        // …while the absent optional scopes survive.
        #expect(try await fixture.foodLog.loadAllFor("").map(\.id) == ["fl-keep"])
        #expect(fixture.favorites.favoriteIDs == ["r_keep"])
        #expect(fixture.reminderSettings.settings.remindD7 == true)
    }

    // MARK: - Import (sync outbox alignment)

    @Test func importInHouseholdEnqueuesOpsLikeManualEdits() async throws {
        let fixture = try makeFixture(household: "home")
        // A synced row that the archive no longer contains → remote soft-delete.
        try await fixture.inventory.saveItems("home", [ingredient("ing-old", "黄油", remoteVersion: 5)])

        let blob = BackupService.encode(BackupArchive(
            data: BackupData(
                inventory: [
                    ingredient("ing-new", "鸡蛋"), // never synced → .create
                    ingredient("ing-upd", "牛奶", remoteVersion: 2), // synced → .update
                ],
                addHistory: [:], shopping: [], customRecipes: [], mealPlan: []
            ),
            foodLog: [logEntry("fl-new", "面包")]
        ))
        try await fixture.controller.importBackup(blob)

        let pending = try await fixture.outbox.loadPending()
        let byId = Dictionary(uniqueKeysWithValues: pending.map { ($0.entityId, $0) })
        #expect(pending.count == 4)
        #expect(pending.allSatisfy { $0.householdId == "home" })

        #expect(byId["ing-new"]?.operation == .create)
        #expect(byId["ing-new"]?.baseVersion == nil)
        #expect(byId["ing-upd"]?.operation == .update)
        #expect(byId["ing-upd"]?.baseVersion == 2)
        #expect(byId["ing-old"]?.operation == .delete)
        #expect(byId["ing-old"]?.baseVersion == 5)
        #expect(byId["fl-new"]?.entityType == .foodLogEntry)
        #expect(byId["fl-new"]?.operation == .create)
        // Full-row patches: the gateway upserts/3-way-merges from these.
        #expect(byId["ing-new"]?.patch["name"] == .string("鸡蛋"))
        #expect(byId["ing-old"]?.patch["name"] == .string("黄油"))
    }

    @Test func importInLocalModeRecordsNoOps() async throws {
        // Personal scope ('' household) has no upload pipeline — the writer's
        // local-first guard makes the enqueue a no-op, not a dropped write.
        let fixture = try makeFixture(household: "")
        let blob = BackupService.encode(BackupArchive(
            data: BackupData(
                inventory: [ingredient("ing-1", "鸡蛋")],
                addHistory: [:], shopping: [], customRecipes: [], mealPlan: []
            ),
            foodLog: [logEntry("fl-1", "面包")]
        ))
        try await fixture.controller.importBackup(blob)
        #expect(try await fixture.outbox.pendingCount() == 0)
    }

    // MARK: - importSyncOps (pure mapping)

    @Test func importSyncOpsSkipsFoodLogWhenScopeAbsent() {
        // nil foodLog produced no local write, so it must produce no ops — the
        // pre-existing entries were NOT deleted locally.
        let previous = BackupController.SyncSnapshot(foodLog: [logEntry("fl-keep", "牛奶", remoteVersion: 3)])
        let ops = BackupController.importSyncOps(
            previous: previous,
            imported: BackupArchive(data: emptyCore())
        )
        #expect(ops.isEmpty)
    }

    @Test func importSyncOpsBaseVersionIsMaxOfArchiveAndExistingRow() {
        // A backup exported BEFORE the row ever synced carries remoteVersion 0,
        // but the live row already exists remotely (e.g. local-mode export →
        // household adoption → restore): the op must address the EXISTING row
        // as an .update on its version — a create-shaped upsert would be
        // silently ignored (`ignoreDuplicates`) and the next merge would roll
        // the restore back. Conversely an archive NEWER than the pre-import
        // snapshot keeps its own (higher) version.
        let archive = BackupArchive(
            data: BackupData(
                inventory: [
                    ingredient("ing-adopted", "鸡蛋"), // archive v0, existing v3
                    ingredient("ing-newer", "牛奶", remoteVersion: 4), // archive v4, existing v2
                ],
                addHistory: [:], shopping: [], customRecipes: [], mealPlan: []
            )
        )
        let previous = BackupController.SyncSnapshot(
            inventory: [
                ingredient("ing-adopted", "鸡蛋", remoteVersion: 3),
                ingredient("ing-newer", "牛奶", remoteVersion: 2),
            ]
        )
        let ops = BackupController.importSyncOps(previous: previous, imported: archive)
        let byId = Dictionary(uniqueKeysWithValues: ops.map { ($0.entityId, $0) })
        #expect(ops.count == 2)
        #expect(byId["ing-adopted"]?.operation == .update)
        #expect(byId["ing-adopted"]?.baseVersion == 3)
        #expect(byId["ing-newer"]?.operation == .update)
        #expect(byId["ing-newer"]?.baseVersion == 4)
    }

    @Test func importSyncOpsSkipsBlankIdsAndKeepsDeleteDiffById() {
        let archive = BackupArchive(
            data: BackupData(
                inventory: [
                    ingredient("", "无 id 行"), // unaddressable → skipped
                    ingredient("ing-both", "同 id 行", remoteVersion: 1),
                ],
                addHistory: [:], shopping: [], customRecipes: [], mealPlan: []
            )
        )
        let previous = BackupController.SyncSnapshot(
            inventory: [
                ingredient("ing-both", "同 id 行", remoteVersion: 1), // survives → no delete
                ingredient("ing-gone", "被还原删掉", remoteVersion: 4),
            ]
        )
        let ops = BackupController.importSyncOps(previous: previous, imported: archive)
        #expect(ops.count == 2)
        #expect(ops.first?.entityId == "ing-both")
        #expect(ops.first?.operation == .update)
        #expect(ops.last?.entityId == "ing-gone")
        #expect(ops.last?.operation == .delete)
        #expect(ops.last?.baseVersion == 4)
    }
}
