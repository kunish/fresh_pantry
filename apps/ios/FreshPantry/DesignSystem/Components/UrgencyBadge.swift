import SwiftUI

/// Status pill driven by the shared `FkStatusStyle` table — the only place a
/// view should render an urgency tint/label. Ported from `FkPill.status`.
///
/// Pass an explicit `FkStatus` (e.g. `.low`) or use the `FreshnessState`
/// initializer for inventory rows.
struct UrgencyBadge: View {
    let status: FkStatus
    var label: String?
    var small: Bool = true

    init(status: FkStatus, label: String? = nil, small: Bool = true) {
        self.status = status
        self.label = label
        self.small = small
    }

    init(state: FreshnessState, label: String? = nil, small: Bool = true) {
        self.init(status: state.fkStatus, label: label, small: small)
    }

    var body: some View {
        let style = FkStatusStyle.of(status)
        Text(label ?? style.label)
            .font(small ? .fkLabelSmall : .fkLabelMedium)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, small ? FkSpacing.sm : 10)
            .padding(.vertical, small ? 3 : 5)
            .background(Capsule().fill(style.background))
    }
}
