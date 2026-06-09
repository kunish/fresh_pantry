import Foundation

/// Tolerant JSON extraction from LLM output. LLMs return code-fenced (```json …
/// ```) or inline JSON, often wrapped in prose. Ported VERBATIM from
/// `lib/utils/ai_json_extract.dart`: try a direct decode, then a fenced match,
/// then a greedy inline `[ … ]` / `{ … }` match, returning nil if none decode.

/// Extracts the first JSON array, returning its parsed elements as `[JSONValue]`.
func extractJsonArrayWithFallbacks(_ input: String) -> [JSONValue]? {
    extractJSONWithFallbacks(
        input,
        // Dart: r'```(?:json)?\s*(\[[\s\S]*?\])\s*```'
        fencedPattern: "```(?:json)?\\s*(\\[[\\s\\S]*?\\])\\s*```",
        // Dart: r'\[[\s\S]*\]'
        inlinePattern: "\\[[\\s\\S]*\\]"
    ) { if case let .array(value) = $0 { return value } else { return nil } }
}

/// Extracts the first JSON object, returning its parsed map as `[String: JSONValue]`.
func extractJsonObjectWithFallbacks(_ input: String) -> [String: JSONValue]? {
    extractJSONWithFallbacks(
        input,
        // Dart: r'```(?:json)?\s*(\{[\s\S]*?\})\s*```'
        fencedPattern: "```(?:json)?\\s*(\\{[\\s\\S]*?\\})\\s*```",
        // Dart: r'\{[\s\S]*\}'
        inlinePattern: "\\{[\\s\\S]*\\}"
    ) { if case let .object(value) = $0 { return value } else { return nil } }
}

// MARK: - Internals

private func extractJSONWithFallbacks<T>(
    _ input: String,
    fencedPattern: String,
    inlinePattern: String,
    cast: (JSONValue) -> T?
) -> T? {
    // 1. Direct decode of the whole string.
    if let direct = decodeJSONValue(input).flatMap(cast) { return direct }

    // 2. Fenced match — the captured group (group 1) is the JSON payload.
    if let fenced = firstMatch(in: input, pattern: fencedPattern, group: 1),
       let value = decodeJSONValue(fenced).flatMap(cast) {
        return value
    }

    // 3. Greedy inline match — group 0 is the whole `[ … ]` / `{ … }` span.
    if let inline = firstMatch(in: input, pattern: inlinePattern, group: 0),
       let value = decodeJSONValue(inline).flatMap(cast) {
        return value
    }

    return nil
}

/// Best-effort decode of a source string into a `JSONValue` (nil on failure),
/// mirroring Dart `_decodeAs` (jsonDecode wrapped in a try/catch).
private func decodeJSONValue(_ source: String) -> JSONValue? {
    guard let data = source.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
}

private func firstMatch(in input: String, pattern: String, group: Int) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let full = NSRange(input.startIndex..., in: input)
    guard let match = regex.firstMatch(in: input, range: full),
          let range = Range(match.range(at: group), in: input)
    else { return nil }
    return String(input[range])
}
