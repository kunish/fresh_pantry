import Foundation

/// UserDefaults-backed expiry-reminder preferences — a `ReminderSettings`
/// Codable blob under `reminder_settings_v1`, byte-compatible with the Flutter
/// `ReminderSettingsRepo` (JSON keys remindD1/remindD3/remindD7/remindDaily) so a
/// future Supabase/household sync can read either side's payload.
///
/// Follows the `FavoritesStore` KV-store template: `@Observable @MainActor`,
/// injectable `UserDefaults` suite, defensive `static decode` (missing /
/// malformed / wrong-shape → `ReminderSettings()` defaults). Exposes the live
/// value plus per-flag setters; each mutation persists synchronously.
@Observable
@MainActor
final class ReminderSettingsStore {
    /// Storage key — matches Flutter `reminder_settings_repo` for sync parity.
    static let storageKey = "reminder_settings_v1"

    private let defaults: UserDefaults

    /// The live reminder settings. Mutate via the setters so writes persist.
    private(set) var settings: ReminderSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: Per-flag mutations

    func setRemindD1(_ value: Bool) { update(settings.copyWith(remindD1: value)) }
    func setRemindD3(_ value: Bool) { update(settings.copyWith(remindD3: value)) }
    func setRemindD7(_ value: Bool) { update(settings.copyWith(remindD7: value)) }
    func setRemindDaily(_ value: Bool) { update(settings.copyWith(remindDaily: value)) }

    /// Sets the local delivery time for all reminders. Hour + minute mutate
    /// together (the DatePicker emits both) so each change persists once.
    func setReminderTime(hour: Int, minute: Int) {
        update(settings.copyWith(reminderHour: hour, reminderMinute: minute))
    }

    /// Toggles summary-only mode: per-item reminders off, daily summary kept as
    /// the lone recall channel (enforced in `ExpiryScheduler`).
    func setSummaryOnly(_ value: Bool) { update(settings.copyWith(summaryOnly: value)) }

    /// Toggles the do-not-disturb window on/off.
    func setQuietHoursEnabled(_ value: Bool) { update(settings.copyWith(quietHoursEnabled: value)) }

    /// Sets the quiet-window bounds. Start + end mutate together (one picker
    /// edit at a time still persists once) so the window stays coherent.
    func setQuietHours(startHour: Int, endHour: Int) {
        update(settings.copyWith(quietStartHour: startHour, quietEndHour: endHour))
    }

    /// Replaces the whole value (used by backup import in a later phase).
    func set(_ next: ReminderSettings) { update(next) }

    // MARK: Flag accessors (drive the Settings toggles generically)

    /// The four toggleable reminder flags, so the UI can bind one row per case.
    enum Flag: CaseIterable { case d1, d3, d7, daily }

    func value(for flag: Flag) -> Bool {
        switch flag {
        case .d1: settings.remindD1
        case .d3: settings.remindD3
        case .d7: settings.remindD7
        case .daily: settings.remindDaily
        }
    }

    func setValue(_ value: Bool, for flag: Flag) {
        switch flag {
        case .d1: setRemindD1(value)
        case .d3: setRemindD3(value)
        case .d7: setRemindD7(value)
        case .daily: setRemindDaily(value)
        }
    }

    // MARK: Persistence (the reusable Codable-blob KV codec)

    /// Sets the in-memory value first (so observers see it immediately), then
    /// writes the JSON blob — mirrors the Flutter notifier's set-before-persist.
    private func update(_ next: ReminderSettings) {
        settings = next
        guard let json = try? DomainJSON.encodeToString(next) else { return }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/malformed/wrong-shape → default settings;
    /// otherwise the lenient-decoded `ReminderSettings` (per-field fallbacks live
    /// in the model's `init(from:)`). Mirrors the Flutter repo's lenient load.
    static func decode(_ raw: String?) -> ReminderSettings {
        guard let raw, !raw.isEmpty,
              let settings = try? DomainJSON.decode(ReminderSettings.self, from: raw)
        else {
            return ReminderSettings()
        }
        return settings
    }
}
