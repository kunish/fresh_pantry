import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FreshPantry

/// Tests for `RecipeCoverStore` — the on-disk cover persistence helper for the
/// custom-recipe cover picker. Exercises the real filesystem (the app-support
/// covers dir); every test cleans up the files it writes.
struct RecipeCoverStoreTests {
    // MARK: Fixtures

    /// Encodes a solid-color `width × height` image to PNG `Data` so we can feed a
    /// known-oversized image to `save` and assert it gets downscaled.
    private func makeImageData(width: Int, height: Int) -> Data {
        let bytesPerRow = width * 4
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, cgImage, nil)
        _ = CGImageDestinationFinalize(destination)
        return output as Data
    }

    /// The pixel dimensions of an encoded image (via ImageIO, no decode-to-bitmap).
    private func dimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    private func cleanup(_ urlString: String) {
        if let url = URL(string: urlString), url.isFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: save — writes a file under the covers dir + returns a file:// URL

    @Test func saveWritesFileURLUnderCoversDirectory() async throws {
        let recipeId = "test-\(UUID().uuidString.lowercased())"
        let urlString = try await RecipeCoverStore.save(makeImageData(width: 200, height: 200), recipeId: recipeId)
        defer { cleanup(urlString) }

        let url = try #require(URL(string: urlString))
        #expect(url.isFileURL)
        #expect(urlString.hasPrefix("file://"))
        #expect(FileManager.default.fileExists(atPath: url.path))

        // The file lives under …/Application Support/RecipeCovers/.
        let coversDir = try RecipeCoverStore.coversDirectory()
        #expect(url.standardizedFileURL.path.hasPrefix(coversDir.standardizedFileURL.path))
    }

    // MARK: save — downscales an oversized image to ≤ 1024px on the longest edge

    @Test func saveDownscalesOversizedImage() async throws {
        let recipeId = "big-\(UUID().uuidString.lowercased())"
        // 2048 × 1536 → longest edge must come down to ≤ 1024.
        let urlString = try await RecipeCoverStore.save(makeImageData(width: 2048, height: 1536), recipeId: recipeId)
        defer { cleanup(urlString) }

        let url = try #require(URL(string: urlString))
        let saved = try Data(contentsOf: url)
        let dims = try #require(dimensions(of: saved))
        #expect(max(dims.width, dims.height) <= 1024)
        // Aspect ratio preserved (4:3) → height stays the shorter edge.
        #expect(dims.width >= dims.height)
    }

    // MARK: save — same recipeId overwrites (stable path)

    @Test func saveTwiceForSameRecipeIdOverwrites() async throws {
        let recipeId = "stable-\(UUID().uuidString.lowercased())"
        let first = try await RecipeCoverStore.save(makeImageData(width: 300, height: 300), recipeId: recipeId)
        let second = try await RecipeCoverStore.save(makeImageData(width: 400, height: 400), recipeId: recipeId)
        defer { cleanup(second) }

        // Same id → same file path (overwrite in place, no orphan).
        #expect(first == second)
        let url = try #require(URL(string: second))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: delete — removes a local cover file

    @Test func deleteRemovesLocalCoverFile() async throws {
        let recipeId = "del-\(UUID().uuidString.lowercased())"
        let urlString = try await RecipeCoverStore.save(makeImageData(width: 200, height: 200), recipeId: recipeId)
        let url = try #require(URL(string: urlString))
        #expect(FileManager.default.fileExists(atPath: url.path))

        RecipeCoverStore.delete(urlString)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: delete — no-op + safe for a remote http URL (and a non-covers path)

    @Test func deleteIsNoOpForRemoteUrl() {
        // Must not throw / must not try to touch the filesystem for a remote URL.
        RecipeCoverStore.delete("https://example.com/cover.jpg")
        RecipeCoverStore.delete("not a url at all")
        // A file:// URL OUTSIDE the covers dir is left untouched.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("keep-me.txt")
        try? "keep".data(using: .utf8)?.write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        RecipeCoverStore.delete(outside.absoluteString)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}
