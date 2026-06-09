import Foundation

/// Pure, SwiftUI-free editable model + validation for the custom-recipe form.
/// Kept separate from the View so the validation + recipe-building logic is unit
/// testable. Mirrors the Dart form's `_validateBasic` / `_validateIngredients`
/// and the `_saveRecipe` build.
struct CustomRecipeDraft: Equatable {
    /// One editable ingredient row (name + numeric quantity + unit).
    struct IngredientRow: Equatable, Identifiable {
        let id: UUID
        var name: String
        var quantity: String
        var unit: String

        init(id: UUID = UUID(), name: String = "", quantity: String = "", unit: String = "g") {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.unit = unit
        }
    }

    /// One editable step row (multi-line text).
    struct StepRow: Equatable, Identifiable {
        let id: UUID
        var text: String

        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    /// Which field an inline error attaches to (the form anchors/scrolls to the
    /// first one). `ingredients` carries a combined message (missing rows /
    /// names / amounts).
    enum Field: Equatable {
        case name
        case category
        case cookingMinutes
        case difficulty
        case ingredients
        case steps
    }

    var name: String
    var category: String
    var cookingMinutes: String
    var difficulty: Int
    var description: String
    var ingredients: [IngredientRow]
    var steps: [StepRow]
    /// Cover image URL — a `file://` path for a locally-picked cover, or a remote
    /// `http(s)` URL for an AI-imported one. nil ⇒ no cover (the category hero
    /// renders). Persisted into `Recipe.imageUrl` on build.
    var imageUrl: String?

    init(
        name: String = "",
        category: String = "家常",
        cookingMinutes: String = "",
        difficulty: Int = 3,
        description: String = "",
        ingredients: [IngredientRow] = [IngredientRow()],
        steps: [StepRow] = [StepRow()],
        imageUrl: String? = nil
    ) {
        self.name = name
        self.category = category
        self.cookingMinutes = cookingMinutes
        self.difficulty = difficulty
        self.description = description
        self.ingredients = ingredients
        self.steps = steps
        self.imageUrl = imageUrl
    }

    /// Seeds the draft from an existing recipe (edit mode). Legacy amount-only
    /// ingredients round-trip via `RecipeIngredient` (quantity/unit already
    /// split on decode), so the visible rows match a reload.
    init(recipe: Recipe) {
        let rows = recipe.ingredients.map {
            IngredientRow(name: $0.name, quantity: $0.quantity, unit: $0.unit)
        }
        let steps = recipe.steps.map { StepRow(text: $0) }
        self.init(
            name: recipe.name,
            category: recipe.category.trimmed.isEmpty ? "家常" : recipe.category,
            cookingMinutes: String(recipe.cookingMinutes),
            difficulty: recipe.difficulty < 1 || recipe.difficulty > 5 ? 3 : recipe.difficulty,
            description: recipe.description,
            ingredients: rows.isEmpty ? [IngredientRow()] : rows,
            steps: steps.isEmpty ? [StepRow()] : steps,
            imageUrl: recipe.imageUrl
        )
    }

    /// Seeds the editable draft from an AI-parsed `RecipeDraft` (URL import).
    /// Mirrors the Dart `recipeDraftToApplyResult` mapping: scalar fields copied
    /// straight across; each ingredient `amount` string split into quantity/unit
    /// via `splitAmount` (numeric prefix + a KNOWN unit only — an unknown
    /// remainder folds back into the quantity text rather than producing junk
    /// units). Empty ingredient/step lists fall back to one blank row so the form
    /// stays editable. `imageUrl` (when the parse found a cover) is carried through
    /// so the form's cover section shows the AI-imported cover; a blank URL → nil.
    init(parsed draft: RecipeDraft) {
        let rows = draft.ingredients.map { ingredient -> IngredientRow in
            let split = CustomRecipeDraft.splitAmount(ingredient.amount.value)
            return IngredientRow(name: ingredient.name.value, quantity: split.quantity, unit: split.unit)
        }
        let stepRows = draft.steps.map { StepRow(text: $0.value) }
        let parsedImageUrl = draft.imageUrl.value?.trimmed
        self.init(
            name: draft.name.value,
            category: draft.category.value.trimmed.isEmpty ? "家常" : draft.category.value,
            cookingMinutes: String(draft.cookingMinutes.value),
            difficulty: draft.difficulty.value < 1 || draft.difficulty.value > 5 ? 3 : draft.difficulty.value,
            description: draft.description.value,
            ingredients: rows.isEmpty ? [IngredientRow()] : rows,
            steps: stepRows.isEmpty ? [StepRow()] : stepRows,
            imageUrl: (parsedImageUrl?.isEmpty == false) ? parsedImageUrl : nil
        )
    }

    /// Splits an AI amount string ("3 个", "1.5kg", "2-3根", "少许") into a
    /// `(quantity, unit)` pair for the editable rows. Ported VERBATIM from the
    /// Dart `appliedIngredientRowFromDraft`:
    ///   * leading numeric token = `^(\d+(?:[./\-]\d+)?)\s*(.*)$` (fraction /
    ///     range / decimal / int);
    ///   * the remainder becomes the unit ONLY when it is a known preset unit;
    ///   * an unknown remainder folds back into the quantity text so we never
    ///     emit a junk unit like "/2个" or "-3根";
    ///   * a non-numeric amount ("少许") stays as quantity text with no unit.
    static func splitAmount(_ rawAmount: String) -> (quantity: String, unit: String) {
        let amount = rawAmount.trimmed
        if amount.isEmpty { return ("", "") }

        guard let match = amountRegex.firstMatch(
            in: amount,
            range: NSRange(amount.startIndex..., in: amount)
        ),
        let qtyRange = Range(match.range(at: 1), in: amount)
        else {
            // Descriptive amount (no numeric prefix) — keep as quantity text.
            return (amount, "")
        }

        let qty = String(amount[qtyRange])
        let remainder: String
        if let remRange = Range(match.range(at: 2), in: amount) {
            remainder = String(amount[remRange]).trimmed
        } else {
            remainder = ""
        }

        let unit = RecipePresets.units.contains(remainder) ? remainder : ""
        let quantityText = unit.isEmpty && !remainder.isEmpty ? "\(qty)\(remainder)" : qty
        return (quantityText, unit)
    }

    /// `^(\d+(?:[./\-]\d+)?)\s*(.*)$` — leading quantity (fraction/range/decimal/
    /// int) + optional remainder. Matches the Dart `_quantityRe`.
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"^(\d+(?:[./\-]\d+)?)\s*(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    // MARK: Reordering (up/down nudges)

    /// Moves the ingredient at `index` by `offset` rows (typically ±1), swapping
    /// with the neighbor. Out-of-bounds targets are a no-op so callers can wire
    /// disabled-edge buttons defensively. Pure model mutation (the form persists
    /// the reordered draft on Save), kept here to stay unit-testable.
    mutating func moveIngredient(from index: Int, by offset: Int) {
        let target = index + offset
        guard ingredients.indices.contains(index), ingredients.indices.contains(target) else { return }
        ingredients.swapAt(index, target)
    }

    /// Moves the step at `index` by `offset` rows (typically ±1), swapping with the
    /// neighbor. Out-of-bounds targets are a no-op. The step badges renumber for
    /// free since the form labels by enumerated offset.
    mutating func moveStep(from index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }

    // MARK: Validation

    /// The trimmed, non-empty cooking steps (the ones that survive to the recipe).
    var trimmedSteps: [String] {
        steps.map { $0.text.trimmed }.filter { !$0.isEmpty }
    }

    /// The complete ingredient rows (name AND quantity-or-unit present), deduped
    /// at build via `RecipeIngredient`. Mirrors Dart `_completeIngredients`.
    var completeIngredients: [RecipeIngredient] {
        ingredients.compactMap { row in
            let name = row.name.trimmed
            let quantity = row.quantity.trimmed
            let unit = row.unit.trimmed
            if name.isEmpty { return nil }
            if quantity.isEmpty && unit.isEmpty { return nil }
            return RecipeIngredient(name: name, quantity: quantity, unit: unit)
        }
    }

    /// Per-field error messages. Empty dictionary ⇒ valid. Mirrors the Dart
    /// validators: name/category non-empty; cookingMinutes a positive int;
    /// difficulty 1–5; at least one COMPLETE ingredient with neither a name nor a
    /// quantity dangling alone; at least one non-empty step.
    func validate() -> [Field: String] {
        var errors: [Field: String] = [:]

        if name.trimmed.isEmpty {
            errors[.name] = "请填入食谱名称"
        }
        if category.trimmed.isEmpty {
            errors[.category] = "请选择分类"
        }
        if let minutes = Int(cookingMinutes.trimmed), minutes > 0 {
            // valid
        } else {
            errors[.cookingMinutes] = "请输入大于 0 的分钟数"
        }
        if difficulty < 1 || difficulty > 5 {
            errors[.difficulty] = "请选择 1-5 颗星"
        }
        if let message = ingredientsError() {
            errors[.ingredients] = message
        }
        if trimmedSteps.isEmpty {
            errors[.steps] = "至少添加一个步骤"
        }

        return errors
    }

    var isValid: Bool { validate().isEmpty }

    /// Ingredient-section error string (nil when valid). A name without a
    /// quantity OR a quantity without a name is an error; a row with neither is
    /// just blank padding. At least one complete row is required.
    private func ingredientsError() -> String? {
        var hasAnyText = false
        var hasComplete = false
        var missingName = false
        var missingAmount = false

        for row in ingredients {
            let name = row.name.trimmed
            // Only a non-empty quantity counts as "amount" — the unit always has a
            // preselected default and isn't user-entered text (mirrors Dart).
            let hasAmount = !row.quantity.trimmed.isEmpty
            if !name.isEmpty || hasAmount { hasAnyText = true }
            if !name.isEmpty && hasAmount {
                hasComplete = true
            } else if name.isEmpty && hasAmount {
                missingName = true
            } else if !name.isEmpty && !hasAmount {
                missingAmount = true
            }
        }

        var parts: [String] = []
        if !hasComplete && !hasAnyText { parts.append("至少一种食材") }
        if missingName { parts.append("食材名称") }
        if missingAmount { parts.append("食材用量") }
        return parts.isEmpty ? nil : parts.joined(separator: "、")
    }

    // MARK: Build

    /// Builds the persisted `Recipe`. A NEW recipe (`existing == nil`) gets a
    /// LOWERCASED UUID id — NOT a `custom_<ms>` id — so it reconciles cleanly with
    /// the server row (the gateway/coordinator match by id and only write UUID
    /// ids remotely; a non-UUID id would never match). An edit preserves the
    /// existing id, tags, and sync metadata.
    func buildRecipe(existing: Recipe? = nil) -> Recipe {
        Recipe(
            id: existing?.id ?? UUID().uuidString.lowercased(),
            name: name.trimmed,
            category: category.trimmed,
            difficulty: difficulty,
            cookingMinutes: Int(cookingMinutes.trimmed) ?? 0,
            description: description.trimmed,
            ingredients: completeIngredients,
            steps: trimmedSteps,
            tags: existing?.tags ?? [],
            imageUrl: imageUrl?.trimmed.isEmpty == false ? imageUrl?.trimmed : nil,
            remoteVersion: existing?.remoteVersion ?? 0,
            clientUpdatedAt: existing?.clientUpdatedAt,
            deletedAt: existing?.deletedAt
        )
    }
}
