import SwiftUI

/// Section title row ported from Flutter `FkSectionHead`: a bold title, an
/// optional count pill, and an optional trailing action button.
struct FkSectionHeader: View {
    let title: String
    var count: Int?
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: FkSpacing.sm) {
            Text(title)
                .font(.fkTitleLarge)
                .foregroundStyle(Color.fkOnSurface)
            if let count {
                Text("\(count)")
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkPrimaryContainer)
                    .padding(.horizontal, FkSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.fkPrimarySoft))
            }
            Spacer(minLength: FkSpacing.sm)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkPrimary)
                    .buttonStyle(.fkPressable)
            }
        }
    }
}
