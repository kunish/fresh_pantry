import Foundation

/// Expiry-reminder preferences for notification scheduling. Local config.
struct ReminderSettings: Equatable, Sendable, Codable {
    /// Default delivery time (09:00 local) — the pre-customization behavior.
    /// Legacy payloads without the time fields decode to this.
    static let defaultReminderHour = 9
    static let defaultReminderMinute = 0
    /// Default quiet-hours window (22:00–07:00 local) — only consulted when
    /// `quietHoursEnabled` is on. Legacy payloads without the quiet fields
    /// decode to these but stay inert (the flag defaults off).
    static let defaultQuietStartHour = 22
    static let defaultQuietEndHour = 7

    var remindD1: Bool
    var remindD3: Bool
    var remindD7: Bool
    var remindDaily: Bool
    /// Local time-of-day when reminders fire (per-item D-N + daily summary).
    var reminderHour: Int
    var reminderMinute: Int
    /// Noise-reduction mode: suppress every per-item D-N reminder and keep only
    /// the single daily summary. The summary is the user's lone recall channel
    /// in this mode, so `ExpiryScheduler` always emits it when this is on (even
    /// if `remindDaily` was toggled off).
    var summaryOnly: Bool
    /// Do-not-disturb window: per-item reminders whose fire time lands inside
    /// the window are suppressed; the daily summary is shifted out instead of
    /// dropped (it stays the recall channel). Off by default for back-compat.
    var quietHoursEnabled: Bool
    /// Quiet-window bounds, local hour-of-day [0...23]. `start == end` means a
    /// zero-width (no-op) window; `start > end` wraps across midnight.
    var quietStartHour: Int
    var quietEndHour: Int

    init(
        remindD1: Bool = true,
        remindD3: Bool = true,
        remindD7: Bool = false,
        remindDaily: Bool = true,
        reminderHour: Int = ReminderSettings.defaultReminderHour,
        reminderMinute: Int = ReminderSettings.defaultReminderMinute,
        summaryOnly: Bool = false,
        quietHoursEnabled: Bool = false,
        quietStartHour: Int = ReminderSettings.defaultQuietStartHour,
        quietEndHour: Int = ReminderSettings.defaultQuietEndHour
    ) {
        self.remindD1 = remindD1
        self.remindD3 = remindD3
        self.remindD7 = remindD7
        self.remindDaily = remindDaily
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.summaryOnly = summaryOnly
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
    }

    /// Enabled D-N offsets, largest-first (used by ExpiryScheduler). Empty in
    /// `summaryOnly` mode — every per-item slot is suppressed there.
    var enabledOffsetDays: [Int] {
        if summaryOnly { return [] }
        var days: [Int] = []
        if remindD7 { days.append(7) }
        if remindD3 { days.append(3) }
        if remindD1 { days.append(1) }
        return days
    }

    /// Whether the daily summary should be emitted: explicitly on, or forced on
    /// by `summaryOnly` (which keeps the summary as the only recall channel).
    var dailySummaryEnabled: Bool { summaryOnly || remindDaily }

    /// "9:00"-style label of the configured delivery time. Single source so the
    /// Settings row and the Dashboard reminder card never drift apart or revert
    /// to a stale hardcoded hour after the user customizes the time.
    var reminderTimeLabel: String {
        "\(reminderHour):" + String(format: "%02d", reminderMinute)
    }

    /// Whether the given local hour-of-day falls inside the active quiet window.
    /// Returns false when quiet hours are off or the window is zero-width.
    /// Handles the wrap-across-midnight case (`start > end`).
    func isWithinQuietHours(hour: Int) -> Bool {
        guard quietHoursEnabled, quietStartHour != quietEndHour else { return false }
        if quietStartHour < quietEndHour {
            // Same-day window, e.g. 01:00–06:00 → [start, end).
            return hour >= quietStartHour && hour < quietEndHour
        }
        // Wraps midnight, e.g. 22:00–07:00 → [start, 24) ∪ [0, end).
        return hour >= quietStartHour || hour < quietEndHour
    }

    func copyWith(
        remindD1: Bool? = nil,
        remindD3: Bool? = nil,
        remindD7: Bool? = nil,
        remindDaily: Bool? = nil,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil,
        summaryOnly: Bool? = nil,
        quietHoursEnabled: Bool? = nil,
        quietStartHour: Int? = nil,
        quietEndHour: Int? = nil
    ) -> ReminderSettings {
        ReminderSettings(
            remindD1: remindD1 ?? self.remindD1,
            remindD3: remindD3 ?? self.remindD3,
            remindD7: remindD7 ?? self.remindD7,
            remindDaily: remindDaily ?? self.remindDaily,
            reminderHour: reminderHour ?? self.reminderHour,
            reminderMinute: reminderMinute ?? self.reminderMinute,
            summaryOnly: summaryOnly ?? self.summaryOnly,
            quietHoursEnabled: quietHoursEnabled ?? self.quietHoursEnabled,
            quietStartHour: quietStartHour ?? self.quietStartHour,
            quietEndHour: quietEndHour ?? self.quietEndHour
        )
    }

    private enum CodingKeys: String, CodingKey {
        case remindD1, remindD3, remindD7, remindDaily, reminderHour, reminderMinute
        case summaryOnly, quietHoursEnabled, quietStartHour, quietEndHour
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(remindD1, forKey: .remindD1)
        try c.encode(remindD3, forKey: .remindD3)
        try c.encode(remindD7, forKey: .remindD7)
        try c.encode(remindDaily, forKey: .remindDaily)
        try c.encode(reminderHour, forKey: .reminderHour)
        try c.encode(reminderMinute, forKey: .reminderMinute)
        try c.encode(summaryOnly, forKey: .summaryOnly)
        try c.encode(quietHoursEnabled, forKey: .quietHoursEnabled)
        try c.encode(quietStartHour, forKey: .quietStartHour)
        try c.encode(quietEndHour, forKey: .quietEndHour)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remindD1 = c.decodeLenientIfPresent(Bool.self, forKey: .remindD1) ?? true
        remindD3 = c.decodeLenientIfPresent(Bool.self, forKey: .remindD3) ?? true
        remindD7 = c.decodeLenientIfPresent(Bool.self, forKey: .remindD7) ?? false
        remindDaily = c.decodeLenientIfPresent(Bool.self, forKey: .remindDaily) ?? true
        reminderHour = c.decodeLenientIfPresent(Int.self, forKey: .reminderHour)
            ?? Self.defaultReminderHour
        reminderMinute = c.decodeLenientIfPresent(Int.self, forKey: .reminderMinute)
            ?? Self.defaultReminderMinute
        summaryOnly = c.decodeLenientIfPresent(Bool.self, forKey: .summaryOnly) ?? false
        quietHoursEnabled = c.decodeLenientIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? false
        quietStartHour = c.decodeLenientIfPresent(Int.self, forKey: .quietStartHour)
            ?? Self.defaultQuietStartHour
        quietEndHour = c.decodeLenientIfPresent(Int.self, forKey: .quietEndHour)
            ?? Self.defaultQuietEndHour
    }
}
