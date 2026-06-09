import SwiftUI

/// Press-feedback button style ported from Flutter `FkAnimatedPressable`:
/// a subtle scale-down on press plus a light sensory tap. Collapses to no
/// animation under Reduce Motion (accessibility + keeps UI tests from hanging
/// on never-settling animations).
struct FkPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? FkMotion.pressScale : 1.0)
            .animation(FkMotion.animation(FkMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FkPressableButtonStyle {
    /// `.buttonStyle(.fkPressable)` — the standard tappable-surface feedback.
    static var fkPressable: FkPressableButtonStyle { FkPressableButtonStyle() }
}

/// Staggered fade+rise entrance ported from Flutter `FkEntrance`. No-op under
/// Reduce Motion (renders fully visible immediately).
struct FkEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        let active = appeared || reduceMotion
        let delay = Double(min(index, FkMotion.staggerMaxItems)) * FkMotion.staggerStep
        return content
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : FkMotion.entranceOffset)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(FkMotion.entrance.delay(delay)) { appeared = true }
            }
    }
}

extension View {
    /// Applies the staggered entrance for the item at `index`.
    func fkEntrance(index: Int = 0) -> some View {
        modifier(FkEntrance(index: index))
    }
}
