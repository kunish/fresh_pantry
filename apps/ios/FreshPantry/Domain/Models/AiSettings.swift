import Foundation

/// User AI provider config (OpenAI-compatible). Stored locally; no sync.
/// `timeout` is serialized as `timeoutSeconds` (Int seconds).
struct AiSettings: Equatable, Sendable, Codable {
    var baseUrl: String
    var apiKey: String
    var model: String
    var timeout: TimeInterval

    init(baseUrl: String, apiKey: String, model: String, timeout: TimeInterval = 60) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
    }

    var isConfigured: Bool {
        !baseUrl.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    static let empty = AiSettings(baseUrl: "", apiKey: "", model: "")

    func copyWith(
        baseUrl: String? = nil,
        apiKey: String? = nil,
        model: String? = nil,
        timeout: TimeInterval? = nil
    ) -> AiSettings {
        AiSettings(
            baseUrl: baseUrl ?? self.baseUrl,
            apiKey: apiKey ?? self.apiKey,
            model: model ?? self.model,
            timeout: timeout ?? self.timeout
        )
    }

    private enum CodingKeys: String, CodingKey {
        case baseUrl, apiKey, model, timeoutSeconds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(baseUrl, forKey: .baseUrl)
        try c.encode(apiKey, forKey: .apiKey)
        try c.encode(model, forKey: .model)
        try c.encode(Int(timeout), forKey: .timeoutSeconds)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseUrl = c.decodeLenientIfPresent(String.self, forKey: .baseUrl) ?? ""
        apiKey = c.decodeLenientIfPresent(String.self, forKey: .apiKey) ?? ""
        model = c.decodeLenientIfPresent(String.self, forKey: .model) ?? ""
        timeout = TimeInterval(c.decodeIntIfPresent(forKey: .timeoutSeconds) ?? 60)
    }
}
