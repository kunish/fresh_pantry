import SwiftUI
import UIKit

/// Category-tinted avatar: a rounded tint box showing the food image when one is
/// available, else the category glyph in the palette ink. Ported from the
/// Flutter avatar box used by `IngredientCard` / the detail hero.
///
/// Remote images (OFF product shots) are downsampled to the rendered size via
/// `RemoteThumbnailStore` rather than `AsyncImage` — list rows would otherwise
/// decode every source at full resolution, the exact memory blow-up the Flutter
/// list covers hit before capping decode to the render box.
struct FkCategoryAvatar: View {
    let imageUrl: String
    let category: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = FkRadius.md
    var iconScale: CGFloat = 0.62

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        let palette = FkCategoryIcon.palette(for: category)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.tint)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    glyph(palette)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: imageUrl) {
                guard let url = URL(string: imageUrl), !imageUrl.isEmpty else {
                    image = nil
                    return
                }
                image = await RemoteThumbnailStore.thumbnail(
                    for: url,
                    maxPixel: Int(size * max(displayScale, 1))
                )
            }
    }

    private func glyph(_ palette: FkCategoryColors) -> some View {
        Image(systemName: FkCategoryIcon.symbol(for: category))
            .font(.system(size: size * iconScale, weight: .semibold))
            .foregroundStyle(palette.ink)
    }
}

/// Fetch-and-downsample cache for remote avatar images. `URLSession.shared`'s
/// URLCache keeps the bytes; this `NSCache` keeps the decoded thumbnails, keyed
/// by URL + pixel size so different render sizes don't collide. `@MainActor`
/// like `RecipeImageStore` (read from view bodies/tasks), with the actual
/// download awaited off-actor by URLSession.
@MainActor
enum RemoteThumbnailStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func thumbnail(for url: URL, maxPixel: Int) async -> UIImage? {
        let key = "\(url.absoluteString)#\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = RecipeImageStore.downsample(data, maxPixel: maxPixel)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
