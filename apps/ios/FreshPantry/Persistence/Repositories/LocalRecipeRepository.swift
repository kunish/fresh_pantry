import Foundation

/// Read-only loader for the bundled HowToCook Chinese recipe corpus
/// (`howtocook.json`, shipped under `Resources/`). Mirrors Flutter's
/// `LocalRecipeRepository`: decode the JSON array ONCE, with per-entry
/// resilience (a single malformed entry is skipped, the rest preserved), and
/// cache the parsed `[Recipe]` for the process lifetime.
///
/// An `actor` so the decode-and-cache happens off the main actor and is safe
/// under Swift 6 strict concurrency. The bundled asset is the read-only
/// explore-tab data source; user/custom recipes come from
/// `CustomRecipeRepository` and are merged on top by the feature store.
actor LocalRecipeRepository {
    /// Resource name of the bundled corpus (XcodeGen globs `Resources/`, so the
    /// file ships in the app bundle as `howtocook.json`).
    static let resourceName = "howtocook"
    static let resourceExtension = "json"

    private let bundle: Bundle
    /// Explicit JSON payload override (tests inject a fixed corpus; production
    /// leaves this `nil` and reads the bundled resource).
    private let payloadOverride: Data?
    private var cache: [Recipe]?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.payloadOverride = nil
    }

    /// Test seam: decode this exact JSON array instead of the bundled resource.
    init(payload: Data) {
        self.bundle = .main
        self.payloadOverride = payload
    }

    /// Decodes the corpus once and caches it. Returns `[]` if the resource is
    /// missing or its top level isn't a JSON array (mirrors the Flutter
    /// `FormatException` → empty behavior — never throws to the caller).
    func loadAll() -> [Recipe] {
        if let cache { return cache }
        let recipes = payloadOverride.map(Self.decode(data:)) ?? Self.decode(from: bundle)
        cache = recipes
        return recipes
    }

    /// Pure decode: load the bundled data, require a top-level array, decode each
    /// entry independently so one bad row can't sink the corpus.
    private static func decode(from bundle: Bundle) -> [Recipe] {
        guard
            let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return decode(data: data)
    }

    /// Per-entry resilient decode (exposed for tests against an injected payload).
    /// The top level must be a JSON array; each element decodes through `Recipe`'s
    /// lenient `Codable`, and any element that fails (wrong type, missing keys) is
    /// skipped — the rest are preserved. Returns `[]` if the top level isn't an
    /// array. Never throws.
    static func decode(data: Data) -> [Recipe] {
        guard let lossy = try? JSONDecoder().decode(LossyRecipeArray.self, from: data) else {
            return []
        }
        return lossy.recipes
    }
}

/// Resilient array container: decodes a JSON array of recipes, skipping any
/// element that fails to decode rather than failing the whole array. Each
/// element is advanced past on failure by decoding a throwaway value, so one bad
/// entry can't desync the unkeyed container.
private struct LossyRecipeArray: Decodable {
    let recipes: [Recipe]

    /// Skip token: decodes ANY single JSON value (scalar, array, or object) via a
    /// single-value container, consuming exactly one element of the unkeyed
    /// container so iteration stays aligned after a malformed recipe. Never throws
    /// for a well-formed JSON value.
    private struct AnyJSON: Decodable {
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { return }
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            if (try? container.decode(String.self)) != nil { return }
            if (try? container.decode([AnyJSON].self)) != nil { return }
            _ = try? container.decode([String: AnyJSON].self)
        }
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Recipe] = []
        while !container.isAtEnd {
            if let recipe = try? container.decode(Recipe.self) {
                decoded.append(recipe)
            } else {
                // Advance past the unparseable element to keep the cursor aligned.
                _ = try? container.decode(AnyJSON.self)
            }
        }
        recipes = decoded
    }
}
