import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// `BackupController.importBackup` must honor its own contract — "any
/// persistence failure propagates out" — for the one scope that reports
/// failure via a Bool instead of throwing: the Keychain-backed AI settings.
/// A rejected write throws `ImportError.aiSettingsPersistFailed` (never a
/// false "已导入"); an accepted write restores the config. Runs on in-memory
/// SwiftData + isolated UserDefaults suites, mirroring `BackupControllerTests`.
@MainActor
struct BackupImportAiSettingsFailureTests {
    /// `SecretStore` fake that rejects every write — models an entitlement-gated
    /// or otherwise refusing Keychain (same fake as `AiSettingsStoreSaveFailureTests`).
    final class RejectingSecretStore: SecretStore, @unchecked Sendable {
        func get(_ key: String) -> Data? { nil }
        func set(_ value: Data, forKey key: String) -> Bool { false }
        func delete(_ key: String) {}
    }

    private func makeController(secrets: SecretStore) throws -> (BackupController, AiSettingsStore) {
        let container = try ModelContainerFactory.makeInMemory()
        let defaults = UserDefaults(suiteName: "test.backupimport.aisettings.\(UUID().uuidString)")!
        let aiStore = AiSettingsStore(secrets: secrets)
        let session = SyncSession(selectedHouseholdId: "", defaults: defaults)
        let controller = BackupController(
            inventory: InventoryRepository(modelContainer: container),
            foodLog: FoodLogRepository(modelContainer: container),
            shopping: ShoppingRepository(modelContainer: container),
            customRecipe: CustomRecipeRepository(modelContainer: container),
            mealPlan: MealPlanRepository(modelContainer: container),
            aiSettings: aiStore,
            favorites: FavoritesStore(defaults: defaults),
            dietaryPreferences: DietaryPreferencesStore(defaults: defaults),
            dietPreference: DietPreferenceStore(defaults: defaults),
            reminderSettings: ReminderSettingsStore(defaults: defaults),
            syncWriter: SyncWriter(
                outbox: SyncOutboxRepository(modelContainer: container),
                coordinator: nil,
                session: session
            ),
            syncSession: session
        )
        return (controller, aiStore)
    }

    /// A minimal blob whose only non-empty scope is a configured AI settings.
    private func blobWithAiSettings() -> String {
        BackupService.encode(BackupArchive(
            data: BackupData(
                inventory: [], addHistory: [:], shopping: [], customRecipes: [], mealPlan: [],
                aiSettings: AiSettings(baseUrl: "https://x/v1", apiKey: "sk", model: "gpt-4o")
            )
        ))
    }

    @Test func rejectedKeychainWriteThrowsInsteadOfFalseSuccess() async throws {
        let (controller, aiStore) = try makeController(secrets: RejectingSecretStore())

        await #expect(throws: BackupController.ImportError.aiSettingsPersistFailed) {
            try await controller.importBackup(blobWithAiSettings())
        }
        // The live value stayed in sync with (empty) storage — no session-only config.
        #expect(aiStore.settings == .empty)
    }

    @Test func acceptedKeychainWriteRestoresAiSettings() async throws {
        let (controller, aiStore) = try makeController(secrets: InMemorySecretStore())

        try await controller.importBackup(blobWithAiSettings())

        #expect(aiStore.settings.apiKey == "sk")
        #expect(aiStore.isConfigured)
    }

    @Test func blobWithoutAiSettingsNeverTouchesTheKeychain() async throws {
        // A nil archive scope is SKIPPED — a rejecting Keychain must not fail
        // the restore of a backup that carries no AI config at all.
        let (controller, aiStore) = try makeController(secrets: RejectingSecretStore())

        let blob = BackupService.encode(BackupArchive(
            data: BackupData(inventory: [], addHistory: [:], shopping: [], customRecipes: [], mealPlan: [])
        ))
        try await controller.importBackup(blob)

        #expect(aiStore.settings == .empty)
    }
}
