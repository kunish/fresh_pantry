import Foundation

/// On-disk cache of the signed-in user's households + the selected household's
/// members, so the 家庭共享 screen is OFFLINE-FIRST. The last successful
/// `refreshHouseholds` (households / members are otherwise a pure network read with
/// no local copy) is persisted to Application Support and seeded SYNCHRONOUSLY in
/// `HouseholdSessionStore.init` on the next launch — before, and instead of when
/// offline, the network round-trip. A returning member then sees their real
/// household + members immediately instead of flashing the misleading
/// 「创建/加入家庭」 onboard form (or an empty member list / blank name) until the
/// fetch lands. The network refresh overwrites the seed.
///
/// IDENTITY-KEYED: a snapshot is seeded back only when its `email` matches the
/// current signed-in user (a different / signed-out identity reads nil), so one
/// user's households can never bleed into another's session — the same RLS-empty /
/// wrong-identity hazard the `HouseholdView` re-load is guarded against.
struct HouseholdCache: Sendable {
    /// One persisted snapshot. `email` is the identity guard; `selectedHouseholdId`
    /// is stored for completeness (the live `SyncSession` scope, restored from
    /// UserDefaults, remains the selection source of truth the seed resolves against).
    struct Snapshot: Codable, Sendable {
        var email: String
        var households: [Household]
        var selectedHouseholdId: String
        var members: [HouseholdMember]
    }

    private let fileURL: URL

    /// Default location: `<ApplicationSupport>/household-cache.json`. Returns nil
    /// when Application Support can't be resolved (the store then stays network-only).
    init?(fileManager: FileManager = .default) {
        guard let dir = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        self.fileURL = dir.appendingPathComponent("household-cache.json")
    }

    /// Test seam: cache at an explicit file URL.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The cached snapshot IFF it belongs to `email` (non-empty, case-insensitive).
    /// A blank email (signed out) or an identity mismatch reads nil — never seed
    /// another user's households. nil when there's no readable cache.
    func read(for email: String?) -> Snapshot? {
        let wanted = (email ?? "").trimmed.lowercased()
        guard !wanted.isEmpty else { return nil }
        guard
            let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
            snapshot.email.trimmed.lowercased() == wanted
        else { return nil }
        return snapshot
    }

    /// Persists the snapshot atomically. Best-effort: a write failure is swallowed
    /// (the next successful refresh retries); the in-memory state is unaffected.
    func write(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
