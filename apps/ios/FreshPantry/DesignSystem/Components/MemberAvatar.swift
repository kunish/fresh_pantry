import SwiftUI

/// Reusable circular avatar: the remote image when `avatarURL` resolves, else
/// the first letter of `displayName` on a soft primary disc. Shared by the
/// settings 「我」 card and the profile detail hero.
struct MemberAvatar: View {
    let displayName: String
    let avatarURL: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.fkPrimarySoft)
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initial
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: some View {
        Text(displayName.trimmed.first.map { String($0).uppercased() } ?? "?")
            .font(size >= 64 ? .fkHeadlineSmall : .fkLabelLarge)
            .foregroundStyle(Color.fkPrimary)
    }
}
