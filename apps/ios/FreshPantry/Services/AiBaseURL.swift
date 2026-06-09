import Foundation

/// Normalizes an OpenAI-compatible API base URL for `AiClient`.
///
/// Accepts common user inputs such as the host root, a `/v1` base, or a full
/// `/v1/chat/completions` endpoint pasted by mistake (services invariant #11).
/// Ported VERBATIM from `lib/utils/ai_base_url.dart`.
func normalizeAiBaseUrl(_ raw: String) -> String {
    var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if url.isEmpty { return url }

    while url.hasSuffix("/") {
        url.removeLast()
    }

    let chatSuffix = "/chat/completions"
    if url.hasSuffix(chatSuffix) {
        url.removeLast(chatSuffix.count)
        while url.hasSuffix("/") {
            url.removeLast()
        }
    }

    if !url.hasSuffix("/v1") && !url.contains("/v1/") {
        url += "/v1"
    }

    return url
}
