import SwiftUI

/// Soft elevation tokens ported from Flutter `AppShadows`. SwiftUI applies one
/// shadow per modifier, so the two-layer card shadow is expressed as a view
/// modifier that stacks both layers.
enum FkShadow {
    /// Small soft shadow (icon button / small card / stat card).
    case soft
    /// Emphasis shadow (primary FAB / centre nav button).
    case strong
}

extension View {
    /// Default two-layer card shadow (near 1px + far 16px).
    func fkCardShadow() -> some View {
        self
            .shadow(color: .fkShadowSoft, radius: 1, x: 0, y: 1)
            .shadow(color: .fkShadowSoft, radius: 8, x: 0, y: 4)
    }

    func fkShadow(_ token: FkShadow) -> some View {
        switch token {
        case .soft:
            return AnyView(shadow(color: .fkShadowSoft, radius: 6, x: 0, y: 4))
        case .strong:
            return AnyView(shadow(color: .fkShadowWarm, radius: 9, x: 0, y: 6))
        }
    }
}
