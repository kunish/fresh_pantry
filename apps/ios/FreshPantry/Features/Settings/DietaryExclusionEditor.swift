import SwiftUI

/// 忌口 keyword editor: a wrap of deletable chips plus an add field, bound to the
/// `DietaryPreferencesStore`. The store owns normalization (trim + lowercase), so
/// this view just forwards raw text to `add`/`remove`.
struct DietaryExclusionEditor: View {
    let store: DietaryPreferencesStore

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            if store.keywords.isEmpty {
                Text("尚未添加忌口关键字")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            } else {
                ChipWrap(keywords: store.sortedKeywords) { store.remove($0) }
            }

            HStack(spacing: FkSpacing.sm) {
                TextField("添加忌口,如 香菜", text: $draft)
                    .font(.fkBodyMedium)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: FkSize.iconMd))
                        .foregroundStyle(canAdd ? Color.fkPrimary : Color.fkOutline)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
        }
        .padding(.vertical, FkSpacing.xs)
    }

    private var canAdd: Bool {
        !draft.trimmed.isEmpty
    }

    private func commit() {
        guard store.add(draft) != nil else { return }
        draft = ""
        fieldFocused = true
    }
}

/// A flow-layout wrap of deletable keyword chips. Uses SwiftUI `Layout` so chips
/// wrap to multiple lines within the row's width.
private struct ChipWrap: View {
    let keywords: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: FkSpacing.sm) {
            ForEach(keywords, id: \.self) { keyword in
                DeletableChip(label: keyword) { onRemove(keyword) }
            }
        }
    }
}

/// A keyword chip with an inline delete affordance.
private struct DeletableChip: View {
    let label: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: FkSpacing.xs) {
            Text(label)
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurface)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.fkOutline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除 \(label)")
        }
        .padding(.leading, FkSpacing.md)
        .padding(.trailing, FkSpacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.fkSurfaceContainer)
                .overlay(Capsule().strokeBorder(Color.fkHair, lineWidth: 1))
        )
    }
}

/// Minimal flow layout: lays children left-to-right, wrapping to a new line when
/// the row width is exceeded. Honors the proposed width so chips reflow.
private struct FlowLayout: Layout {
    var spacing: CGFloat = FkSpacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
