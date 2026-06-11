import Foundation

/// The user's personal profile (`profiles` table). Per-user, NOT household-scoped.
/// Decodes the Supabase row's snake_case keys lenient-with-defaults, matching the
/// household DTOs' tolerant style: an absent optional field is "" (未设置).
struct UserProfile: Equatable, Sendable, Codable {
    var id: String
    var email: String
    var displayName: String
    var nickname: String
    var avatarPath: String

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case nickname
        case avatarPath = "avatar_path"
    }

    init(
        id: String = "",
        email: String = "",
        displayName: String = "",
        nickname: String = "",
        avatarPath: String = ""
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.nickname = nickname
        self.avatarPath = avatarPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            email: c.decodeLenientIfPresent(String.self, forKey: .email) ?? "",
            displayName: c.decodeLenientIfPresent(String.self, forKey: .displayName) ?? "",
            nickname: c.decodeLenientIfPresent(String.self, forKey: .nickname) ?? "",
            avatarPath: c.decodeLenientIfPresent(String.self, forKey: .avatarPath) ?? ""
        )
    }
}
