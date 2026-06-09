import Foundation
import Testing
@testable import FreshPantry

/// Covers the clipboard recipe-URL detection that pre-fills the AI-import field:
/// extraction + host gate (reusing `extractSupportedRecipeURL`) and the per-URL
/// ignore cooldown. The pasteboard + clock are injected so nothing touches the
/// real clipboard or wall clock.
@MainActor
struct ClipboardRecipeURLDetectorTests {
    private static let lanfan = "https://lanfanapp.com/recipe/abc"
    private static let xiachufang = "https://www.xiachufang.com/recipe/123/"

    @Test func extractsSupportedURLFromSurroundingText() async {
        let detector = ClipboardRecipeURLDetector(reader: { "快看这个 \(Self.xiachufang) 超好吃" })
        #expect(await detector.peek() == Self.xiachufang)
    }

    @Test func acceptsLanfanLink() async {
        let detector = ClipboardRecipeURLDetector(reader: { Self.lanfan })
        #expect(await detector.peek() == Self.lanfan)
    }

    @Test func unsupportedAndLookalikeHostsReturnNil() async {
        #expect(await ClipboardRecipeURLDetector(reader: { "https://evil-xiachufang.com/x" }).peek() == nil)
        #expect(await ClipboardRecipeURLDetector(reader: { "https://example.com/recipe" }).peek() == nil)
    }

    @Test func bareHostIsNotOffered() async {
        // Detection requires an EXPLICIT http(s) URL (unlike `ensureRecipeUrl`), so a
        // bare "xiachufang.com/..." on the clipboard is not auto-suggested.
        let detector = ClipboardRecipeURLDetector(reader: { "xiachufang.com/recipe/123" })
        #expect(await detector.peek() == nil)
    }

    @Test func emptyOrMissingClipboardReturnsNil() async {
        #expect(await ClipboardRecipeURLDetector(reader: { "just some text" }).peek() == nil)
        #expect(await ClipboardRecipeURLDetector(reader: { "" }).peek() == nil)
        #expect(await ClipboardRecipeURLDetector(reader: { nil }).peek() == nil)
    }

    @Test func cooldownSuppressesSameURLThenExpires() async {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let detector = ClipboardRecipeURLDetector(
            ignoreCooldown: 1800,
            reader: { Self.xiachufang },
            clock: { now }
        )
        #expect(await detector.peek() == Self.xiachufang)
        detector.markIgnored(Self.xiachufang)
        #expect(await detector.peek() == nil)            // within cooldown → suppressed
        now = now.addingTimeInterval(1801)
        #expect(await detector.peek() == Self.xiachufang) // cooldown expired → offered again
    }

    @Test func differentURLNotSuppressed() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let detector = ClipboardRecipeURLDetector(
            ignoreCooldown: 1800,
            reader: { Self.xiachufang },
            clock: { now }
        )
        detector.markIgnored(Self.lanfan)                // a DIFFERENT url is on cooldown
        #expect(await detector.peek() == Self.xiachufang) // so this one is still offered
    }
}
