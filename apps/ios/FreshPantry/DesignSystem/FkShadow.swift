import SwiftUI

/// Soft elevation ported from Flutter `AppShadows`. SwiftUI applies one shadow
/// per modifier, so the two-layer card shadow is expressed as a view modifier
/// that stacks both layers.
extension View {
    /// Default two-layer card shadow (near 1px + far 16px).
    func fkCardShadow() -> some View {
        self
            .shadow(color: .fkShadowSoft, radius: 1, x: 0, y: 1)
            .shadow(color: .fkShadowSoft, radius: 8, x: 0, y: 4)
    }
}
