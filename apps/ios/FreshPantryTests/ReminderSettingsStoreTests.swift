import Foundation
import Testing
@testable import FreshPantry

/// Tests for the UserDefaults-backed reminder-settings KV store: default values,
/// per-flag mutation, JSON-blob persistence round-trip via an injected suite,
/// and defensive decode.
@MainActor
struct ReminderSettingsStoreTests {
    /// A fresh isolated suite per test so persisted blobs never leak between runs.
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.reminder.\(UUID().uuidString)")!
    }

    // MARK: Defaults

    @Test func freshStoreUsesModelDefaults() {
        let store = ReminderSettingsStore(defaults: suite())
        #expect(store.settings == ReminderSettings()) // D1/D3 on, D7 off, daily on
        #expect(store.settings.remindD1)
        #expect(store.settings.remindD3)
        #expect(!store.settings.remindD7)
        #expect(store.settings.remindDaily)
    }

    // MARK: Flag mutation

    @Test func perFlagSettersMutateAndPersist() {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)

        store.setRemindD7(true)
        store.setRemindDaily(false)
        #expect(store.settings.remindD7)
        #expect(!store.settings.remindDaily)
        // Untouched flags retain their values.
        #expect(store.settings.remindD1)
        #expect(store.settings.remindD3)

        // A new store over the same suite reads the persisted blob.
        let reloaded = ReminderSettingsStore(defaults: defaults)
        #expect(reloaded.settings.remindD7)
        #expect(!reloaded.settings.remindDaily)
        #expect(reloaded.settings.remindD1)
    }

    // MARK: Round-trip / wire shape

    @Test func persistedBlobIsCodableJsonWithFlutterKeys() throws {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)
        store.setRemindD7(true)

        let raw = try #require(defaults.string(forKey: ReminderSettingsStore.storageKey))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        // Flutter-compatible keys present.
        #expect(object["remindD1"] as? Bool == true)
        #expect(object["remindD7"] as? Bool == true)
        #expect(object["remindDaily"] as? Bool == true)
        // Decodes back to the same settings.
        #expect(ReminderSettingsStore.decode(raw).remindD7)
    }

    @Test func setReplacesWholeValue() {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)
        store.set(ReminderSettings(remindD1: false, remindD3: false, remindD7: true, remindDaily: false))
        let reloaded = ReminderSettingsStore(defaults: defaults)
        #expect(!reloaded.settings.remindD1)
        #expect(reloaded.settings.remindD7)
    }

    // MARK: Defensive decode

    @Test func decodeHandlesNilEmptyAndMalformed() {
        #expect(ReminderSettingsStore.decode(nil) == ReminderSettings())
        #expect(ReminderSettingsStore.decode("") == ReminderSettings())
        #expect(ReminderSettingsStore.decode("not json") == ReminderSettings())
        // Partial blob: present keys honored, missing keys fall back to defaults.
        let partial = ReminderSettingsStore.decode(#"{"remindD1":false}"#)
        #expect(!partial.remindD1)
        #expect(partial.remindD3) // default true
        #expect(partial.remindDaily) // default true
    }
}
