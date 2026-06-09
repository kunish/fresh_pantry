import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for the AI utility ports: `normalizeAiBaseUrl` (services
/// invariant #11) and the fenced/inline/prose-tolerant JSON extraction helpers.
struct AiUtilsTests {
    // MARK: - normalizeAiBaseUrl

    @Test func normalizeAppendsV1ToHostRoot() {
        #expect(normalizeAiBaseUrl("https://example.com") == "https://example.com/v1")
    }

    @Test func normalizeLeavesV1Base() {
        #expect(normalizeAiBaseUrl("https://example.com/v1") == "https://example.com/v1")
    }

    @Test func normalizeStripsTrailingSlash() {
        #expect(normalizeAiBaseUrl("https://example.com/v1/") == "https://example.com/v1")
    }

    @Test func normalizeStripsChatCompletionsSuffix() {
        #expect(
            normalizeAiBaseUrl("https://example.com/v1/chat/completions") == "https://example.com/v1"
        )
    }

    @Test func normalizeStripsChatCompletionsThenAppendsV1WhenAbsent() {
        // host-root + /chat/completions pasted -> strip suffix, then append /v1.
        #expect(
            normalizeAiBaseUrl("https://example.com/chat/completions") == "https://example.com/v1"
        )
    }

    @Test func normalizeTrimsWhitespace() {
        #expect(normalizeAiBaseUrl("  https://example.com/v1  ") == "https://example.com/v1")
    }

    @Test func normalizeKeepsV1InMidPath() {
        // Already contains /v1/ mid-path (proxy style) -> left as-is.
        #expect(normalizeAiBaseUrl("https://proxy.test/v1/openai") == "https://proxy.test/v1/openai")
    }

    @Test func normalizeEmptyStaysEmpty() {
        #expect(normalizeAiBaseUrl("   ") == "")
    }

    // MARK: - extractJsonArrayWithFallbacks

    @Test func extractsDirectArray() {
        let result = extractJsonArrayWithFallbacks(#"[{"a":1}]"#)
        #expect(result?.count == 1)
        if case let .object(map) = result?.first {
            #expect(map["a"] == .int(1))
        } else {
            Issue.record("expected an object element")
        }
    }

    @Test func extractsFencedArray() {
        let raw = """
        ```json
        [1, 2, 3]
        ```
        """
        let result = extractJsonArrayWithFallbacks(raw)
        #expect(result == [.int(1), .int(2), .int(3)])
    }

    @Test func extractsProseWrappedInlineArray() {
        let raw = "这是结果: [\"a\", \"b\"] 完毕"
        let result = extractJsonArrayWithFallbacks(raw)
        #expect(result == [.string("a"), .string("b")])
    }

    @Test func extractArrayReturnsNilForInvalid() {
        #expect(extractJsonArrayWithFallbacks("no json here") == nil)
    }

    // MARK: - extractJsonObjectWithFallbacks

    @Test func extractsDirectObject() {
        let result = extractJsonObjectWithFallbacks(#"{"name":"x"}"#)
        #expect(result?["name"] == .string("x"))
    }

    @Test func extractsFencedObject() {
        let raw = """
        说明文字
        ```json
        {"error":"oops"}
        ```
        尾注
        """
        let result = extractJsonObjectWithFallbacks(raw)
        #expect(result?["error"] == .string("oops"))
    }

    @Test func extractsProseWrappedInlineObject() {
        let raw = "返回:{\"k\":42}。"
        let result = extractJsonObjectWithFallbacks(raw)
        #expect(result?["k"] == .int(42))
    }

    @Test func extractObjectReturnsNilForInvalid() {
        #expect(extractJsonObjectWithFallbacks("plain text") == nil)
    }
}
