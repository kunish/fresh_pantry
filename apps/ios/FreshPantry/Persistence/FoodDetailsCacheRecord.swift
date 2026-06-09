import Foundation
import SwiftData

/// SwiftData row for the food-details cache. The blueprint flags that the
/// single SharedPreferences JSON blob is better split into its own store in
/// Swift — this is that store. `cacheKey` (`barcode:<…>` / `name:<…>`) is the
/// natural key; `payloadJSON` holds the full `FoodDetails.toJson()` incl.
/// `cacheVersion: 5`.
@Model
final class FoodDetailsCacheRecord {
    @Attribute(.unique) var cacheKey: String = ""
    var cacheVersion: Int = FoodDetails.cacheVersion
    var payloadJSON: String = ""

    init(cacheKey: String, details: FoodDetails) {
        self.cacheKey = cacheKey
        apply(details)
    }

    func apply(_ details: FoodDetails) {
        cacheVersion = FoodDetails.cacheVersion
        payloadJSON = (try? DomainJSON.encodeToString(details)) ?? payloadJSON
    }

    func details() throws -> FoodDetails {
        try DomainJSON.decode(FoodDetails.self, from: payloadJSON)
    }

    /// Cache key for an ingredient: `barcode:<barcode>` when present, else
    /// `name:<normalizeCacheKey(name)>` (mirrors `foodDetailsCacheKeyFor`).
    static func cacheKey(for ingredient: Ingredient) -> String {
        if let barcode = ingredient.barcode, !barcode.trimmed.isEmpty {
            return "barcode:\(barcode)"
        }
        return "name:\(normalizeCacheKey(ingredient.name))"
    }
}

/// `normalizeCacheKey`: trim, lowercase, collapse whitespace to a single space.
/// Ported from `lib/utils/normalize_cache_key.dart`.
func normalizeCacheKey(_ raw: String) -> String {
    let collapsed = raw.trimmed.lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return collapsed
}
