import Foundation
import SwiftData

/// SwiftData row caching the CURRENT user's profile (single row). Drives instant
/// display on launch and powers the pending-upload retry when a save couldn't
/// reach the backend. NOT a per-member store — only "me" lives here.
@Model
final class ProfileRecord {
    var id: String = ""
    var email: String = ""
    var displayName: String = ""
    var nickname: String = ""
    var avatarPath: String = ""
    /// True when the local edit hasn't been confirmed pushed to the backend yet.
    var pendingUpload: Bool = false

    init(profile: UserProfile, pendingUpload: Bool) {
        id = profile.id
        email = profile.email
        displayName = profile.displayName
        nickname = profile.nickname
        avatarPath = profile.avatarPath
        self.pendingUpload = pendingUpload
    }

    func profile() -> UserProfile {
        UserProfile(id: id, email: email, displayName: displayName, nickname: nickname, avatarPath: avatarPath)
    }
}
