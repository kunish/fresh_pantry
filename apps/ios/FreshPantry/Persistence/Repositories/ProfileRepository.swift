import Foundation
import SwiftData

/// Sendable snapshot of the cached profile (never hand a `@Model` across the
/// actor boundary).
struct LocalProfile: Sendable, Equatable {
    let profile: UserProfile
    let pendingUpload: Bool
}

/// Single-row local store for the current user's profile. `save` replaces the row
/// (clear-then-insert) so there is never more than one.
@ModelActor
actor ProfileRepository {
    func load() throws -> LocalProfile? {
        guard let row = try modelContext.fetch(FetchDescriptor<ProfileRecord>()).first else { return nil }
        return LocalProfile(profile: row.profile(), pendingUpload: row.pendingUpload)
    }

    func save(_ profile: UserProfile, pendingUpload: Bool) throws {
        for row in try modelContext.fetch(FetchDescriptor<ProfileRecord>()) {
            modelContext.delete(row)
        }
        modelContext.insert(ProfileRecord(profile: profile, pendingUpload: pendingUpload))
        try modelContext.save()
    }

    /// Test/diagnostic helper: number of cached rows (must stay ≤ 1).
    func count() throws -> Int {
        try modelContext.fetch(FetchDescriptor<ProfileRecord>()).count
    }
}
