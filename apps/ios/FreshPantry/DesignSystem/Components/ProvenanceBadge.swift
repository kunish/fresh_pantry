import SwiftUI

/// Small colored dot marking a proposal field's provenance (origin + whether the
/// user hand-edited it). Ported from Flutter `ProvenanceBadge`.
///
/// `userEdited` always wins (手改). Otherwise the dot reflects the data's
/// origin: AI inference, system-derived (shopping), or hand-filled (manual add).
struct ProvenanceBadge: View {
    let origin: FieldOrigin
    var userEdited: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }

    private var color: Color {
        if userEdited { return .fkWarn }
        switch origin {
        case .ai: return .fkPrimary
        case .system: return .fkOutline
        case .user: return .fkWarn
        }
    }

    private var label: String {
        if userEdited { return "手改" }
        switch origin {
        case .ai: return "AI 推断"
        case .system: return "系统"
        case .user: return "手填"
        }
    }
}
