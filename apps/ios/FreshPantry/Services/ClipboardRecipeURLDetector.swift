import Foundation
import UIKit

/// Peeks the system clipboard for a supported recipe URL to OFFER on the custom-
/// recipe form (create mode), mirroring the Dart `ClipboardUrlDetector`. When the
/// user opens 新建食谱 with a懒饭/下厨房 link already copied, the form can expand the
/// AI-import banner and pre-fill it instead of making them paste by hand.
///
/// Holds a per-URL ignore cooldown so dismissing a suggestion doesn't immediately
/// re-offer the same link on the next open. `@MainActor` because it reads
/// `UIPasteboard` and is driven from the view; the reader + clock are injectable so
/// the cooldown / extraction logic is unit-testable without the real pasteboard or
/// wall clock.
@MainActor
final class ClipboardRecipeURLDetector {
    /// Clipboard text source. Injectable for tests; the default reads the system
    /// pasteboard (privacy-gated — see `readPasteboard`).
    typealias Reader = @MainActor () async -> String?
    /// Wall-clock source. Injectable so cooldown tests are deterministic.
    typealias Clock = @MainActor () -> Date

    private let read: Reader
    private let clock: Clock
    private let ignoreCooldown: TimeInterval

    private var ignoredURL: String?
    private var ignoredAt: Date?

    init(
        ignoreCooldown: TimeInterval = 30 * 60,
        reader: Reader? = nil,
        clock: @escaping Clock = { Date() }
    ) {
        self.ignoreCooldown = ignoreCooldown
        self.read = reader ?? ClipboardRecipeURLDetector.readPasteboard
        self.clock = clock
    }

    /// The first supported recipe URL on the clipboard, or nil when it is missing,
    /// from an unsupported host, or suppressed by this URL's cooldown window.
    func peek() async -> String? {
        guard let text = await read(), !text.isEmpty,
              let url = extractSupportedRecipeURL(in: text)
        else { return nil }

        if url == ignoredURL, let ignoredAt,
           clock().timeIntervalSince(ignoredAt) < ignoreCooldown {
            return nil
        }
        return url
    }

    /// Suppresses `url` for the cooldown window so a dismissed suggestion doesn't
    /// re-appear the next time the form opens with the same clipboard contents.
    func markIgnored(_ url: String) {
        ignoredURL = url
        ignoredAt = clock()
    }

    /// Privacy-respecting read: only surface clipboard CONTENT (which triggers the
    /// system "pasted from" banner) once iOS first reports a probable web URL is
    /// present, so opening the form with a non-URL clipboard stays silent.
    private static func readPasteboard() async -> String? {
        let pasteboard = UIPasteboard.general
        // `detectedPatterns` only reports WHETHER a URL is present (no content access →
        // no "pasted from" banner). It's the keyPath family (the `DetectionPattern`
        // family has no async variant), so the pattern is `\.probableWebURL`.
        let wanted: Set<PartialKeyPath<UIPasteboard.DetectedValues>> = [\.probableWebURL]
        guard let detected = try? await pasteboard.detectedPatterns(for: wanted),
              detected.contains(\UIPasteboard.DetectedValues.probableWebURL)
        else { return nil }
        // Only now read the actual text (this surfaces the system banner — justified,
        // since a recipe link is present and we're about to offer it).
        return pasteboard.string
    }
}
