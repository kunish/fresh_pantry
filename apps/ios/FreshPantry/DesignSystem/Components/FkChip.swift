import SwiftUI

/// Selectable filter chip ported from Flutter `FkSectionHead`-style pills, used
/// by the storage-area filter row. Selected → primary fill; idle → white with a
/// hairline border.
struct FkChip: View {
    let label: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(displayLabel)
                .font(.fkLabelMedium)
                .foregroundStyle(isSelected ? Color.fkOnPrimary : Color.fkOnSurface)
                .padding(.horizontal, FkSpacing.lg)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.fkPrimary : Color.fkSurfaceContainerLowest)
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Color.clear : Color.fkHair,
                                lineWidth: 1
                            )
                        )
                )
        }
        .buttonStyle(.fkPressable)
    }

    private var displayLabel: String {
        if let count, count > 0 { return "\(label) · \(count)" }
        return label
    }
}
