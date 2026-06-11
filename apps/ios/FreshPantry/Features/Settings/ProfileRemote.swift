import Foundation

/// The profile store's remote seam. `RemotePantryRepository` conforms in
/// production; tests inject a fake to exercise the optimistic-save / pending
/// paths without a live backend. Kept narrow on purpose (interface segregation).
protocol ProfileRemote: Sendable {
    func loadMyProfile() async throws -> UserProfile?
    func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws
    func uploadAvatar(_ data: Data) async throws -> String
    /// Public URL for a stored avatar path, or nil for an empty path. Synchronous
    /// (no actor hop) so SwiftUI rows can build the URL inline.
    nonisolated func avatarPublicURL(path: String) -> URL?
}
