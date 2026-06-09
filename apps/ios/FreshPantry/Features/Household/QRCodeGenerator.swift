import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Generates a crisp QR-code bitmap for an invite URL (parity with the Flutter
/// `QrImageView(data: inviteUrl, size: 200)`), plus a `Transferable` PNG wrapper so
/// it can be shared as a real `fresh-pantry-invite.png` attachment.
///
/// Pure / dependency-free (CoreImage is a system framework). The raw
/// `CIQRCodeGenerator` output is ~1px per module, so it is scaled UP in CI space
/// and rasterized through a CACHED `CIContext` (creating one per call is costly).
enum QRCodeGenerator {
    private static let context = CIContext()

    /// A high-res QR bitmap for `string`, or nil if encoding fails. `scale` is the
    /// CI-space upscale (12 → a ~400px bitmap for a typical URL QR; downscales
    /// cleanly into a 200pt view and is large enough for the shared PNG).
    static func image(from string: String, scale: CGFloat = 12) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A `Transferable` PNG so `ShareLink(item:)` exports an actual
/// `fresh-pantry-invite.png` file (matching the Flutter share), rather than a
/// SwiftUI `Image` whose filename/encoding can't be controlled.
struct InviteQRImage: Transferable {
    let image: UIImage
    var fileName: String = "fresh-pantry-invite.png"

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { qr in
            qr.image.pngData() ?? Data()
        }
        .suggestedFileName { $0.fileName }
    }
}
