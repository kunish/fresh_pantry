import SwiftUI

/// Category-tinted avatar: a rounded tint box showing the food image when one is
/// available, else the category glyph in the palette ink. Ported from the
/// Flutter avatar box used by `IngredientCard` / the detail hero.
struct FkCategoryAvatar: View {
    let imageUrl: String
    let category: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = FkRadius.md
    var iconScale: CGFloat = 0.62

    var body: some View {
        let palette = FkCategoryIcon.palette(for: category)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.tint)
            .frame(width: size, height: size)
            .overlay {
                if let url = URL(string: imageUrl), !imageUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            glyph(palette)
                        }
                    }
                } else {
                    glyph(palette)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func glyph(_ palette: FkCategoryColors) -> some View {
        Image(systemName: FkCategoryIcon.symbol(for: category))
            .font(.system(size: size * iconScale, weight: .semibold))
            .foregroundStyle(palette.ink)
    }
}
