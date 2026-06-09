import SwiftUI

/// Empty / no-results placeholder ported from Flutter `FkEmptyState`, styled to
/// mirror `ContentUnavailableView`: a soft circular icon badge, a bold title,
/// and a muted message.
struct FkEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: FkSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.fkPrimarySoft)
                    .frame(width: 64, height: 64)
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.fkPrimary)
            }
            VStack(spacing: FkSpacing.xs) {
                Text(title)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                if let message {
                    Text(message)
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FkSpacing.xl)
        .padding(.vertical, 60)
    }
}
