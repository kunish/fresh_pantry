import Foundation

/// Sub-value inside `Recipe.ingredients`. Value-equal over name/quantity/unit/
/// amount. `amount` is derived from quantity+unit when not supplied (mirrors the
/// Dart constructor's `_composeAmount`).
struct RecipeIngredient: Equatable, Sendable, Codable {
    var name: String
    var quantity: String
    var unit: String
    var amount: String

    init(name: String, quantity: String = "", unit: String = "", amount: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.amount = amount ?? RecipeIngredient.composeAmount(quantity, unit)
    }

    /// trim both; both empty -> ''; q empty -> u; u empty -> q; else "$q$u".
    static func composeAmount(_ quantity: String, _ unit: String) -> String {
        let q = quantity.trimmed
        let u = unit.trimmed
        if q.isEmpty && u.isEmpty { return "" }
        if q.isEmpty { return u }
        if u.isEmpty { return q }
        return "\(q)\(u)"
    }

    /// Legacy parse: trims, empty -> ('',''); uses `parseLeadingQuantity`:
    /// nil -> ('', wholeTrimmed); else (magnitude, remainder).
    private static func parseLegacyAmount(_ amount: String) -> (quantity: String, unit: String) {
        let trimmed = amount.trimmed
        if trimmed.isEmpty { return ("", "") }
        guard let parsed = QuantityText.parseLeadingQuantity(trimmed) else {
            return ("", trimmed)
        }
        return (parsed.magnitude, parsed.remainder)
    }

    /// True when the quantity is a plain numeric magnitude `scaledBy` can scale.
    var isScalable: Bool { Double(quantity.trimmed) != nil }

    /// Multiplies the numeric magnitude by `factor`, recomposing amount.
    /// `factor == 1` is a no-op preserving an explicit amount; a non-numeric
    /// quantity is returned unchanged.
    func scaledBy(_ factor: Double) -> RecipeIngredient {
        if factor == 1 { return self }
        guard let magnitude = Double(quantity.trimmed) else { return self }
        return RecipeIngredient(
            name: name,
            quantity: QuantityText.formatQuantity(magnitude * factor),
            unit: unit
        )
    }

    func copyWith(
        name: String? = nil,
        quantity: String? = nil,
        unit: String? = nil,
        amount: String? = nil
    ) -> RecipeIngredient {
        let preservedAmount = amount ?? (quantity == nil && unit == nil ? self.amount : nil)
        return RecipeIngredient(
            name: name ?? self.name,
            quantity: quantity ?? self.quantity,
            unit: unit ?? self.unit,
            amount: preservedAmount
        )
    }

    private enum CodingKeys: String, CodingKey { case name, quantity, unit, amount }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(amount, forKey: .amount)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let amount = c.decodeLenientIfPresent(String.self, forKey: .amount) ?? ""
        // "New shape" when either quantity or unit key is present.
        let hasNewShape = c.contains(.quantity) || c.contains(.unit)
        let name = c.decodeLenientIfPresent(String.self, forKey: .name) ?? ""
        if hasNewShape {
            self.init(
                name: name,
                quantity: c.decodeLenientIfPresent(String.self, forKey: .quantity) ?? "",
                unit: c.decodeLenientIfPresent(String.self, forKey: .unit) ?? "",
                amount: amount
            )
        } else {
            let parts = RecipeIngredient.parseLegacyAmount(amount)
            self.init(name: name, quantity: parts.quantity, unit: parts.unit, amount: amount)
        }
    }
}

/// De-duplicates by case-insensitive trimmed name, keeping the FIRST occurrence.
/// Must run at EVERY recipe entry point (matches `shoppingItemNameKey`).
func dedupeRecipeIngredients(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
    var seen = Set<String>()
    var result: [RecipeIngredient] = []
    for ingredient in ingredients {
        if seen.insert(ingredient.name.trimmed.lowercased()).inserted {
            result.append(ingredient)
        }
    }
    return result
}

/// Recipe entity. Identity (Hashable/Equatable) is by `id` ONLY.
struct Recipe: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var category: String
    var difficulty: Int
    var cookingMinutes: Int
    var description: String
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var tags: [String]
    var imageUrl: String?
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    var syncMetadata: SyncMetadata {
        SyncMetadata(
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            deletedAt: deletedAt
        )
    }

    /// `'难度未设置'` when difficulty <= 0, else `'难度 N/5'` with N clamped 1...5.
    var difficultyLabel: String {
        if difficulty <= 0 { return "难度未设置" }
        let level = min(max(difficulty, 1), 5)
        return "难度 \(level)/5"
    }

    init(
        id: String,
        name: String,
        category: String,
        difficulty: Int,
        cookingMinutes: Int,
        description: String,
        ingredients: [RecipeIngredient],
        steps: [String],
        tags: [String] = [],
        imageUrl: String? = nil,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.difficulty = difficulty
        self.cookingMinutes = cookingMinutes
        self.description = description
        // Dedupe at the value-type entry point too (every entry point routes here).
        self.ingredients = dedupeRecipeIngredients(ingredients)
        self.steps = steps
        self.tags = tags
        self.imageUrl = imageUrl
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, difficulty, cookingMinutes, description
        case ingredients, steps, tags, imageUrl
        case remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(cookingMinutes, forKey: .cookingMinutes)
        try c.encode(description, forKey: .description)
        try c.encode(ingredients, forKey: .ingredients)
        try c.encode(steps, forKey: .steps)
        try c.encode(tags, forKey: .tags)
        try c.encodeAlways(imageUrl, forKey: .imageUrl)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawIngredients = c.decodeLenientIfPresent([RecipeIngredient].self, forKey: .ingredients) ?? []
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            name: c.decodeLenientIfPresent(String.self, forKey: .name) ?? "",
            category: c.decodeLenientIfPresent(String.self, forKey: .category) ?? "",
            difficulty: c.decodeIntIfPresent(forKey: .difficulty) ?? 0,
            cookingMinutes: c.decodeIntIfPresent(forKey: .cookingMinutes) ?? 30,
            description: c.decodeLenientIfPresent(String.self, forKey: .description) ?? "",
            ingredients: rawIngredients,
            steps: c.decodeLenientIfPresent([String].self, forKey: .steps) ?? [],
            tags: c.decodeLenientIfPresent([String].self, forKey: .tags) ?? [],
            imageUrl: c.decodeLenientIfPresent(String.self, forKey: .imageUrl),
            remoteVersion: c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0,
            clientUpdatedAt: c.decodeISODateIfPresent(forKey: .clientUpdatedAt),
            deletedAt: c.decodeISODateIfPresent(forKey: .deletedAt)
        )
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        category: String? = nil,
        difficulty: Int? = nil,
        cookingMinutes: Int? = nil,
        description: String? = nil,
        ingredients: [RecipeIngredient]? = nil,
        steps: [String]? = nil,
        tags: [String]? = nil,
        imageUrl: String? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> Recipe {
        Recipe(
            id: id ?? self.id,
            name: name ?? self.name,
            category: category ?? self.category,
            difficulty: difficulty ?? self.difficulty,
            cookingMinutes: cookingMinutes ?? self.cookingMinutes,
            description: description ?? self.description,
            ingredients: ingredients ?? self.ingredients,
            steps: steps ?? self.steps,
            tags: tags ?? self.tags,
            imageUrl: imageUrl ?? self.imageUrl,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}

extension String {
    /// Dart `.trim()` parity — strips leading/trailing whitespace & newlines.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
