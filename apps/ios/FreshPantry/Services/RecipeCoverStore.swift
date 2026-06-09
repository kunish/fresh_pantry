import Foundation

/// Persists a picked recipe cover image to local disk and hands back a stable
/// `file://` URL string the form stores in `Recipe.imageUrl` (rendered straight
/// through `AsyncImage(url:)`, which already resolves `file://` paths).
///
/// SYNC LIMITATION (acceptable parity, NOT a bug): a `file://` cover is
/// device-local. It round-trips inside the recipe's synced payload as a path
/// string that will NOT resolve on another device — the same limitation the
/// Flutter app had for locally-picked images. The cover BYTES are never uploaded;
/// only the path travels. AI-imported covers carry a remote `http(s)` URL instead
/// and DO render everywhere. We deliberately do not upload image bytes here.
enum RecipeCoverStore {
    /// Longest edge (in pixels) a picked cover is downscaled to before JPEG
    /// re-encode — matches the AI-vision import bound so payloads stay small.
    static let maxImageDimension = 1024
    /// JPEG quality for the re-encoded cover.
    static let jpegQuality: CGFloat = 0.7

    /// The application-support subdirectory all covers live under.
    private static let directoryName = "RecipeCovers"

    /// Downscales + re-encodes `imageData` to a bounded JPEG and writes it to
    /// `…/Application Support/RecipeCovers/<recipeId>.jpg`, creating the directory
    /// if needed. Returns the file's `absoluteString` (a `file://…` URL string).
    ///
    /// Saving twice for the same `recipeId` OVERWRITES the existing file (the path
    /// is derived from the id), so an edit replaces the cover in place. The
    /// downscale runs OFF the calling actor so a large image never blocks UI.
    static func save(_ imageData: Data, recipeId: String) async throws -> String {
        let maxDimension = maxImageDimension
        let quality = jpegQuality
        let jpeg = await Task.detached {
            ImageDownscaler.jpegData(from: imageData, maxDimension: maxDimension, quality: quality)
        }.value
        guard let jpeg else { throw CoverError.notAnImage }

        let directory = try coversDirectory()
        let fileName = sanitizedFileName(recipeId)
        let fileURL = directory.appendingPathComponent(fileName).appendingPathExtension("jpg")
        try jpeg.write(to: fileURL, options: .atomic)
        return fileURL.absoluteString
    }

    /// Best-effort removal of a previously-saved cover. A no-op (and never throws)
    /// for a remote `http(s)` URL or any path NOT under the covers directory — so
    /// clearing an AI-imported remote cover can't try to delete a real file.
    static func delete(_ urlString: String) {
        guard let url = URL(string: urlString), url.isFileURL else { return }
        guard let directory = try? coversDirectory() else { return }
        // Only touch files that actually live under our covers directory.
        guard url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Helpers

    /// The covers directory, created on first use.
    static func coversDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Reduces an arbitrary id to a safe, non-empty file-name stem (alphanumerics
    /// + `-`/`_` survive; anything else collapses so a stray id can't escape the
    /// directory or break the path). Falls back to a fresh UUID when empty.
    private static func sanitizedFileName(_ recipeId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = recipeId.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? UUID().uuidString.lowercased() : result
    }

    enum CoverError: Error {
        /// The picked data could not be decoded into an image.
        case notAnImage
    }
}
