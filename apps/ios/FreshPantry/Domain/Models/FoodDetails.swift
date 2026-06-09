import Foundation

/// Per-100g macro nutrition facts (Open Food Facts). Every field is nullable.
struct NutritionFacts: Equatable, Sendable, Codable {
    var energyKcal: Double?  // kcal / 100g
    var protein: Double?     // g / 100g
    var carbs: Double?       // g / 100g
    var fat: Double?         // g / 100g

    init(energyKcal: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.energyKcal = energyKcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    var hasAny: Bool {
        energyKcal != nil || protein != nil || carbs != nil || fat != nil
    }

    /// Build from an OFF `nutriments` map (per-100g keys). Returns nil when no
    /// usable macro is present (don't store empty facts).
    static func fromOffNutriments(_ n: [String: Any]) -> NutritionFacts? {
        let facts = NutritionFacts(
            energyKcal: toDouble(n["energy-kcal_100g"]),
            protein: toDouble(n["proteins_100g"]),
            carbs: toDouble(n["carbohydrates_100g"]),
            fat: toDouble(n["fat_100g"])
        )
        return facts.hasAny ? facts : nil
    }

    static func toDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmed) }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case energyKcal, protein, carbs, fat }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeAlways(energyKcal, forKey: .energyKcal)
        try c.encodeAlways(protein, forKey: .protein)
        try c.encodeAlways(carbs, forKey: .carbs)
        try c.encodeAlways(fat, forKey: .fat)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal = c.decodeDoubleIfPresent(forKey: .energyKcal)
        protein = c.decodeDoubleIfPresent(forKey: .protein)
        carbs = c.decodeDoubleIfPresent(forKey: .carbs)
        fat = c.decodeDoubleIfPresent(forKey: .fat)
    }
}

/// Cached enriched food metadata (OFF/AI) + per-100g nutrition. Cache value
/// object — `toJson` writes a literal `cacheVersion: 5` that must move in
/// lockstep with the cache constant or stale caches won't invalidate.
struct FoodDetails: Equatable, Sendable, Codable {
    /// Cache schema version literal — bumped to 5 when nutrition was added.
    static let cacheVersion = 5

    var displayName: String
    var description: String
    var imageUrl: String?
    var category: String
    var storage: IconType
    var shelfLifeDays: Int?
    var source: String
    var fetchedAt: Date
    var nutrition: NutritionFacts?

    init(
        displayName: String,
        description: String,
        imageUrl: String?,
        category: String,
        storage: IconType,
        shelfLifeDays: Int?,
        source: String,
        fetchedAt: Date,
        nutrition: NutritionFacts? = nil
    ) {
        self.displayName = displayName
        self.description = description
        self.imageUrl = imageUrl
        self.category = category
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
        self.source = source
        self.fetchedAt = fetchedAt
        self.nutrition = nutrition
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, description, imageUrl, category, storage
        case shelfLifeDays, source, fetchedAt, nutrition, cacheVersion
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(description, forKey: .description)
        try c.encodeAlways(imageUrl, forKey: .imageUrl)
        try c.encode(category, forKey: .category)
        try c.encode(storage.rawValue, forKey: .storage)
        try c.encodeAlways(shelfLifeDays, forKey: .shelfLifeDays)
        try c.encode(source, forKey: .source)
        try c.encode(JSONDate.iso8601(fetchedAt), forKey: .fetchedAt)
        try c.encodeAlways(nutrition, forKey: .nutrition)
        try c.encode(FoodDetails.cacheVersion, forKey: .cacheVersion)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = c.decodeLenientIfPresent(String.self, forKey: .displayName) ?? ""
        description = c.decodeLenientIfPresent(String.self, forKey: .description) ?? ""
        imageUrl = c.decodeLenientIfPresent(String.self, forKey: .imageUrl)
        category = c.decodeLenientIfPresent(String.self, forKey: .category) ?? ""
        storage = IconType.fromName(c.decodeLenientIfPresent(String.self, forKey: .storage))
        shelfLifeDays = c.decodeIntIfPresent(forKey: .shelfLifeDays)
        source = c.decodeLenientIfPresent(String.self, forKey: .source) ?? ""
        // tryParse OR epoch-0-UTC fallback when missing/unparseable.
        let rawFetchedAt = c.decodeLenientIfPresent(String.self, forKey: .fetchedAt)
        fetchedAt = JSONDate.fromJSONValue(rawFetchedAt) ?? Date(timeIntervalSince1970: 0)
        nutrition = c.decodeLenientIfPresent(NutritionFacts.self, forKey: .nutrition)
    }
}
