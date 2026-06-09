import SwiftUI

/// A labeled form row wrapper: a small caption above an arbitrary control.
/// Shared by the add-ingredient form so every field gets the same label
/// typography + spacing without re-deriving it per call site.
struct FkFormField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            Text(label)
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tappable "value pill" that reads like a select control: shows the current
/// value with a trailing chevron, styled on the surface-container ramp. Used by
/// the category / storage pickers (each opens an `FkPickerSheet`).
struct FkValuePill: View {
    let value: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FkSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: FkSize.iconSm, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
                Text(value)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: FkSpacing.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fkOutline)
            }
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
            )
        }
        .buttonStyle(.fkPressable)
    }
}

/// Plain text-field styled to match `FkValuePill` (same container ramp), used by
/// the name / custom-amount inputs in the add form.
struct FkTextFieldPill: View {
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .done
    var onCommit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.fkTitleMedium)
            .foregroundStyle(Color.fkOnSurface)
            .keyboardType(keyboard)
            .submitLabel(submitLabel)
            .onSubmit(onCommit)
            .padding(.horizontal, FkSpacing.md)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                    .fill(Color.fkSurfaceContainer)
            )
    }
}
