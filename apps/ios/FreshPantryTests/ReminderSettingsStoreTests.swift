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
        // Reminder time defaults to the pre-customization 09:00.
        #expect(store.settings.reminderHour == 9)
        #expect(store.settings.reminderMinute == 0)
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

    // MARK: Reminder time

    @Test func setReminderTimeMutatesAndPersists() {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)

        store.setReminderTime(hour: 20, minute: 30)
        #expect(store.settings.reminderHour == 20)
        #expect(store.settings.reminderMinute == 30)
        // Untouched flags retain their values.
        #expect(store.settings.remindD1)
        #expect(store.settings.remindDaily)

        // A new store over the same suite reads the persisted time back.
        let reloaded = ReminderSettingsStore(defaults: defaults)
        #expect(reloaded.settings.reminderHour == 20)
        #expect(reloaded.settings.reminderMinute == 30)
    }

    @Test func persistedBlobCarriesReminderTimeKeys() throws {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)
        store.setReminderTime(hour: 7, minute: 45)

        let raw = try #require(defaults.string(forKey: ReminderSettingsStore.storageKey))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        #expect(object["reminderHour"] as? Int == 7)
        #expect(object["reminderMinute"] as? Int == 45)
    }

    @Test func legacyBlobWithoutTimeFieldsDecodesToNineOClock() {
        // Pre-customization blobs (old backups / previous versions) carry only
        // the four flags — the time must fall back to 09:00, not fail decode.
        let legacy = ReminderSettingsStore.decode(
            #"{"remindD1":true,"remindD3":true,"remindD7":false,"remindDaily":true}"#
        )
        #expect(legacy.reminderHour == 9)
        #expect(legacy.reminderMinute == 0)
        #expect(legacy == ReminderSettings())
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

    // MARK: Noise-reduction defaults + setters

    @Test func freshStoreHasNoiseReductionOff() {
        let store = ReminderSettingsStore(defaults: suite())
        #expect(!store.settings.summaryOnly)
        #expect(!store.settings.quietHoursEnabled)
        #expect(store.settings.quietStartHour == 22)
        #expect(store.settings.quietEndHour == 7)
    }

    @Test func setSummaryOnlyMutatesAndPersists() {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)
        store.setSummaryOnly(true)
        #expect(store.settings.summaryOnly)
        // Per-item offsets collapse to empty under summary-only.
        #expect(store.settings.enabledOffsetDays.isEmpty)
        let reloaded = ReminderSettingsStore(defaults: defaults)
        #expect(reloaded.settings.summaryOnly)
    }

    @Test func setQuietHoursMutatesAndPersists() {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)
        store.setQuietHoursEnabled(true)
        store.setQuietHours(startHour: 21, endHour: 6)
        #expect(store.settings.quietHoursEnabled)
        #expect(store.settings.quietStartHour == 21)
        #expect(store.settings.quietEndHour == 6)
        let reloaded = ReminderSettingsStore(defaults: defaults)
        #expect(reloaded.settings.quietHoursEnabled)
        #expect(reloaded.settings.quietStartHour == 21)
        #expect(reloaded.settings.quietEndHour == 6)
    }

    @Test func persistedBlobCarriesNoiseReductionKeys() throws {
        let defaults = suite()
        let store = ReminderSettingsStore(defaults: defaults)
        store.setSummaryOnly(true)
        store.setQuietHoursEnabled(true)
        store.setQuietHours(startHour: 23, endHour: 8)

        let raw = try #require(defaults.string(forKey: ReminderSettingsStore.storageKey))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        #expect(object["summaryOnly"] as? Bool == true)
        #expect(object["quietHoursEnabled"] as? Bool == true)
        #expect(object["quietStartHour"] as? Int == 23)
        #expect(object["quietEndHour"] as? Int == 8)
    }

    @Test func legacyBlobWithoutNoiseFieldsDecodesToDefaultsOff() {
        // Pre-feature blobs (round-2 backups) carry the four flags + time only —
        // the noise-reduction fields must fall back to off/defaults, not fail.
        let legacy = ReminderSettingsStore.decode(
            #"{"remindD1":true,"remindD3":true,"remindD7":false,"remindDaily":true,"reminderHour":20,"reminderMinute":30}"#
        )
        #expect(!legacy.summaryOnly)
        #expect(!legacy.quietHoursEnabled)
        #expect(legacy.quietStartHour == 22)
        #expect(legacy.quietEndHour == 7)
        // Existing fields still decode.
        #expect(legacy.reminderHour == 20)
        #expect(legacy.reminderMinute == 30)
    }

    // MARK: Quiet-window membership (cross-midnight / same-day / edge cases)

    @Test func quietWindowWrapsAcrossMidnight() {
        let s = ReminderSettings(
            quietHoursEnabled: true, quietStartHour: 22, quietEndHour: 7
        )
        #expect(s.isWithinQuietHours(hour: 23)) // late night
        #expect(s.isWithinQuietHours(hour: 0))  // midnight
        #expect(s.isWithinQuietHours(hour: 6))  // early morning
        #expect(s.isWithinQuietHours(hour: 22)) // inclusive start
        #expect(!s.isWithinQuietHours(hour: 7)) // exclusive end
        #expect(!s.isWithinQuietHours(hour: 12))
    }

    @Test func quietWindowSameDayRange() {
        let s = ReminderSettings(
            quietHoursEnabled: true, quietStartHour: 10, quietEndHour: 15
        )
        #expect(s.isWithinQuietHours(hour: 10)) // inclusive start
        #expect(s.isWithinQuietHours(hour: 14))
        #expect(!s.isWithinQuietHours(hour: 15)) // exclusive end
        #expect(!s.isWithinQuietHours(hour: 9))
        #expect(!s.isWithinQuietHours(hour: 23))
    }

    @Test func quietWindowZeroWidthAndDisabledAreNoOps() {
        // Zero-width window (start == end) suppresses nothing.
        let zero = ReminderSettings(
            quietHoursEnabled: true, quietStartHour: 8, quietEndHour: 8
        )
        #expect(!zero.isWithinQuietHours(hour: 8))
        #expect(!zero.isWithinQuietHours(hour: 0))
        // Flag off → never within quiet hours regardless of bounds.
        let off = ReminderSettings(
            quietHoursEnabled: false, quietStartHour: 22, quietEndHour: 7
        )
        #expect(!off.isWithinQuietHours(hour: 23))
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
