import SwiftUI

/// Reusable surface card ported from Flutter `FkCard`: a rounded container with
/// the two-layer card shadow. `background` defaults to the lowest surface; pass
/// a custom fill for tinted variants.
struct FkCard<Content: View>: View {
    var padding: CGFloat = FkSpacing.lg
    var cornerRadius: CGFloat = FkRadius.xl
    var background: Color = .fkSurfaceContainerLowest
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            )
            .fkCardShadow()
    }
}
