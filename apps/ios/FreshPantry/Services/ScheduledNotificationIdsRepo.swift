import Foundation

/// Persists the set of OS notification ids scheduled in the current session, so
/// a later resync can cancel the ones it no longer needs. Mirrors
/// `lib/storage/scheduled_notification_ids_repo.dart`.
///
/// These ids are device-local and ephemeral (regenerated from inventory on every
/// reschedule), so plain `UserDefaults` is sufficient — no SwiftData. Decodes
/// defensively: a missing or malformed blob yields an empty list.
struct ScheduledNotificationIdsRepo {
    /// Storage key for the persisted id array.
    static let storageKey = "fresh_pantry.notification_ids"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last-scheduled ids, or an empty list if absent / malformed.
    func load() -> [Int] {
        guard let raw = defaults.string(forKey: Self.storageKey),
              let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return ids
    }

    /// Persists the current scheduled-id set as a JSON array.
    func save(_ ids: [Int]) {
        guard let data = try? JSONEncoder().encode(ids),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(raw, forKey: Self.storageKey)
    }
}
