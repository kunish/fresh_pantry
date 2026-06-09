import Foundation

/// Expiry-reminder preferences for notification scheduling. Local config.
struct ReminderSettings: Equatable, Sendable, Codable {
    var remindD1: Bool
    var remindD3: Bool
    var remindD7: Bool
    var remindDaily: Bool

    init(
        remindD1: Bool = true,
        remindD3: Bool = true,
        remindD7: Bool = false,
        remindDaily: Bool = true
    ) {
        self.remindD1 = remindD1
        self.remindD3 = remindD3
        self.remindD7 = remindD7
        self.remindDaily = remindDaily
    }

    /// Enabled D-N offsets, largest-first (used by ExpiryScheduler).
    var enabledOffsetDays: [Int] {
        var days: [Int] = []
        if remindD7 { days.append(7) }
        if remindD3 { days.append(3) }
        if remindD1 { days.append(1) }
        return days
    }

    func copyWith(
        remindD1: Bool? = nil,
        remindD3: Bool? = nil,
        remindD7: Bool? = nil,
        remindDaily: Bool? = nil
    ) -> ReminderSettings {
        ReminderSettings(
            remindD1: remindD1 ?? self.remindD1,
            remindD3: remindD3 ?? self.remindD3,
            remindD7: remindD7 ?? self.remindD7,
            remindDaily: remindDaily ?? self.remindDaily
        )
    }

    private enum CodingKeys: String, CodingKey {
        case remindD1, remindD3, remindD7, remindDaily
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(remindD1, forKey: .remindD1)
        try c.encode(remindD3, forKey: .remindD3)
        try c.encode(remindD7, forKey: .remindD7)
        try c.encode(remindDaily, forKey: .remindDaily)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remindD1 = c.decodeLenientIfPresent(Bool.self, forKey: .remindD1) ?? true
        remindD3 = c.decodeLenientIfPresent(Bool.self, forKey: .remindD3) ?? true
        remindD7 = c.decodeLenientIfPresent(Bool.self, forKey: .remindD7) ?? false
        remindDaily = c.decodeLenientIfPresent(Bool.self, forKey: .remindDaily) ?? true
    }
}
