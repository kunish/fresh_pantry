import Foundation
import Testing
@testable import FreshPantry

/// Codec tests for the v2 envelope's OPTIONAL iOS-only scopes (`foodLog` /
/// `favorites` / `dietaryExclusions` / `dietPreferences` / `reminderSettings`):
/// the encode→decode round-trip, the absent-key ⇒ nil backward compatibility
/// with pre-expansion v2 blobs, and the same strict shape validation the core
/// scopes get. The core five-key contract stays pinned by `BackupServiceTests`.
struct BackupArchiveCodecTests {
    private let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Fixtures

    private func emptyCore() -> BackupData {
        BackupData(inventory: [], addHistory: [:], shopping: [], customRecipes: [], mealPlan: [])
    }

    private func sampleArchive() -> BackupArchive {
        BackupArchive(
            data: emptyCore(),
            foodLog: [
                FoodLogEntry(
                    id: "fl-1", name: "牛奶", category: "乳品蛋类", outcome: .consumed,
                    loggedAt: Date(timeIntervalSince1970: 1_699_000_000),
                    wasExpiring: true, remoteVersion: 2
                ),
                FoodLogEntry(
                    id: "fl-2", name: "面包", outcome: .wasted,
                    loggedAt: Date(timeIntervalSince1970: 1_699_100_000)
                ),
            ],
            favorites: ["r_1", "r_2"],
            dietaryExclusions: ["花生", "辣"],
            dietPreferences: ["低脂", "素食"],
            reminderSettings: ReminderSettings(remindD7: true, reminderHour: 8, quietHoursEnabled: true)
        )
    }

    // MARK: Round-trip

    @Test func roundTripPreservesOptionalScopes() throws {
        let original = sampleArchive()
        let decoded = try BackupService.decodeArchive(BackupService.encode(original, exportedAt: exportedAt))

        // FoodLogEntry equality is id-only, so assert the payload fields too.
        #expect(decoded.foodLog?.count == 2)
        let first = try #require(decoded.foodLog?.first)
        #expect(first.id == "fl-1")
        #expect(first.name == "牛奶")
        #expect(first.category == "乳品蛋类")
        #expect(first.outcome == .consumed)
        #expect(first.loggedAt == Date(timeIntervalSince1970: 1_699_000_000))
        #expect(first.wasExpiring)
        #expect(first.remoteVersion == 2)

        #expect(decoded.favorites == ["r_1", "r_2"])
        #expect(decoded.dietaryExclusions == ["花生", "辣"])
        #expect(decoded.dietPreferences == ["低脂", "素食"])
        #expect(decoded.reminderSettings == original.reminderSettings)
    }

    @Test func emptyOptionalScopesRoundTripAsEmptyNotNil() throws {
        // "backed up empty" must survive distinct from "not backed up": a fresh
        // install's export carries empty lists, and restoring it clears the scopes.
        let original = BackupArchive(
            data: emptyCore(),
            foodLog: [],
            favorites: [],
            dietaryExclusions: [],
            dietPreferences: [],
            reminderSettings: ReminderSettings()
        )
        let decoded = try BackupService.decodeArchive(BackupService.encode(original, exportedAt: exportedAt))
        #expect(decoded.foodLog == [])
        #expect(decoded.favorites == [])
        #expect(decoded.dietaryExclusions == [])
        #expect(decoded.dietPreferences == [])
        #expect(decoded.reminderSettings == ReminderSettings())
    }

    // MARK: Backward compatibility (pre-expansion blobs)

    @Test func legacyBlobWithoutOptionalKeysDecodesNilScopes() throws {
        // The minimal pre-expansion v2 envelope: nil (= absent), NOT empty, so
        // an import skips these scopes instead of wiping them.
        let decoded = try BackupService.decodeArchive(#"{"version":2,"data":{}}"#)
        #expect(decoded.foodLog == nil)
        #expect(decoded.favorites == nil)
        #expect(decoded.dietaryExclusions == nil)
        #expect(decoded.dietPreferences == nil)
        #expect(decoded.reminderSettings == nil)
        #expect(decoded.data.inventory.isEmpty)
    }

    @Test func coreOnlyEncodeOmitsOptionalKeys() throws {
        // The `BackupData` overload (and any nil archive field) writes no key —
        // a core-only blob is shape-identical to the pre-expansion output.
        let blob = BackupService.encode(emptyCore(), exportedAt: exportedAt)
        let root = try JSONSerialization.jsonObject(with: blob.data(using: .utf8)!) as! [String: Any]
        let payload = root["data"] as! [String: Any]
        #expect(payload["foodLog"] == nil)
        #expect(payload["favorites"] == nil)
        #expect(payload["dietaryExclusions"] == nil)
        #expect(payload["dietPreferences"] == nil)
        #expect(payload["reminderSettings"] == nil)
        #expect(root["version"] as? Int == 2)
    }

    @Test func coreDecodeStillReturnsBackupDataFromExpandedBlob() throws {
        // The narrow `decode` keeps working against a blob that carries the
        // optional scopes (it just drops them).
        let blob = BackupService.encode(sampleArchive(), exportedAt: exportedAt)
        let data = try BackupService.decode(blob)
        #expect(data == emptyCore())
    }

    // MARK: Strict shape validation

    @Test func decodeRejectsNonListFoodLog() {
        #expect(throws: BackupService.BackupError.format("Backup payload for \"foodLog\" must be a JSON list")) {
            try BackupService.decodeArchive(#"{"version":2,"data":{"foodLog":{}}}"#)
        }
    }

    @Test func decodeRejectsNonListFavorites() {
        #expect(throws: BackupService.BackupError.format("Backup payload for \"favorites\" must be a JSON list")) {
            try BackupService.decodeArchive(#"{"version":2,"data":{"favorites":{}}}"#)
        }
    }

    @Test func decodeRejectsNonObjectReminderSettings() {
        #expect(throws: BackupService.BackupError.format("Backup payload for \"reminderSettings\" must be a JSON object")) {
            try BackupService.decodeArchive(#"{"version":2,"data":{"reminderSettings":[]}}"#)
        }
    }

    // MARK: Per-element tolerance

    @Test func foodLogRowWithoutLoggedAtIsDropped() throws {
        // One dirty row (missing loggedAt → FoodLogEntry decode throws) must not
        // abort the import — same per-row tolerance as the live repositories.
        let blob = #"""
        {"version":2,"data":{"foodLog":[
            {"id":"bad","name":"鸡蛋"},
            {"id":"good","name":"牛奶","outcome":"consumed","loggedAt":"2026-01-02T08:30:00.000Z"}
        ]}}
        """#
        let decoded = try BackupService.decodeArchive(blob)
        #expect(decoded.foodLog?.map(\.id) == ["good"])
    }

    @Test func nonStringFavoritesElementsAreSkipped() throws {
        let decoded = try BackupService.decodeArchive(#"{"version":2,"data":{"favorites":["r_1",42,null,"r_2"]}}"#)
        #expect(decoded.favorites == ["r_1", "r_2"])
    }
}
