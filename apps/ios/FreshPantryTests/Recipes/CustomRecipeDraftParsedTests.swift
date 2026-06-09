import Foundation
import Testing
@testable import FreshPantry

/// `CustomRecipeDraft(parsed:)` — the AI-import mapping from a parsed
/// `RecipeDraft` into the editable form draft. Covers the amount→quantity/unit
/// split (numeric prefix + known-unit-only gate, parity with the Dart
/// `appliedIngredientRowFromDraft`) and the empty-list fallbacks.
struct CustomRecipeDraftParsedTests {
    private func draft(
        name: String = "番茄炒蛋",
        category: String = "家常",
        cookingMinutes: Int = 15,
        difficulty: Int = 3,
        ingredients: [(String, String)] = [],
        steps: [String] = []
    ) -> RecipeDraft {
        RecipeDraft(
            sourceUrl: "https://www.xiachufang.com/recipe/1",
            name: .ai(name),
            category: .ai(category),
            cookingMinutes: .ai(cookingMinutes),
            difficulty: .ai(difficulty),
            description: .ai(""),
            imageUrl: DraftField(value: nil, source: .ai),
            ingredients: ingredients.map { RecipeIngredientDraft(name: .ai($0.0), amount: .ai($0.1)) },
            steps: steps.map { DraftField<String>.ai($0) }
        )
    }

    // MARK: Scalar mapping

    @Test func mapsScalarFields() {
        let form = CustomRecipeDraft(parsed: draft(cookingMinutes: 25, difficulty: 4, steps: ["a", "b"]))
        #expect(form.name == "番茄炒蛋")
        #expect(form.category == "家常")
        #expect(form.cookingMinutes == "25")
        #expect(form.difficulty == 4)
        #expect(form.steps.map(\.text) == ["a", "b"])
    }

    @Test func blankCategoryFallsBackToHome() {
        let form = CustomRecipeDraft(parsed: draft(category: "   "))
        #expect(form.category == "家常")
    }

    @Test func outOfRangeDifficultyFallsBackToThree() {
        #expect(CustomRecipeDraft(parsed: draft(difficulty: 0)).difficulty == 3)
        #expect(CustomRecipeDraft(parsed: draft(difficulty: 9)).difficulty == 3)
    }

    // MARK: Amount split

    @Test func splitsNumberAndKnownUnit() {
        let pair = CustomRecipeDraft.splitAmount("2 个")
        #expect(pair.quantity == "2")
        #expect(pair.unit == "个")
    }

    @Test func splitsNumberAndKnownUnitNoSpace() {
        let pair = CustomRecipeDraft.splitAmount("1.5kg")
        #expect(pair.quantity == "1.5")
        #expect(pair.unit == "kg")
    }

    @Test func unknownUnitFoldsIntoQuantity() {
        // "瓣" is NOT in RecipePresets.units → kept as quantity text, no junk unit.
        let pair = CustomRecipeDraft.splitAmount("3瓣")
        #expect(pair.quantity == "3瓣")
        #expect(pair.unit == "")
    }

    @Test func rangeWithoutKnownUnitStaysQuantity() {
        let pair = CustomRecipeDraft.splitAmount("2-3根")
        // "根" IS a known unit → quantity is the leading range token, unit "根".
        #expect(pair.quantity == "2-3")
        #expect(pair.unit == "根")
    }

    @Test func descriptiveAmountStaysQuantity() {
        let pair = CustomRecipeDraft.splitAmount("少许")
        #expect(pair.quantity == "少许")
        #expect(pair.unit == "")
    }

    @Test func emptyAmountSplitsEmpty() {
        let pair = CustomRecipeDraft.splitAmount("  ")
        #expect(pair.quantity == "")
        #expect(pair.unit == "")
    }

    @Test func mapsIngredientRows() {
        let form = CustomRecipeDraft(parsed: draft(ingredients: [("番茄", "2个"), ("盐", "少许")]))
        #expect(form.ingredients.count == 2)
        #expect(form.ingredients[0].name == "番茄")
        #expect(form.ingredients[0].quantity == "2")
        #expect(form.ingredients[0].unit == "个")
        #expect(form.ingredients[1].name == "盐")
        #expect(form.ingredients[1].quantity == "少许")
        #expect(form.ingredients[1].unit == "")
    }

    // MARK: Empty-list fallbacks

    @Test func emptyIngredientsFallBackToOneBlankRow() {
        let form = CustomRecipeDraft(parsed: draft(ingredients: []))
        #expect(form.ingredients.count == 1)
        #expect(form.ingredients.first?.name == "")
    }

    @Test func emptyStepsFallBackToOneBlankRow() {
        let form = CustomRecipeDraft(parsed: draft(steps: []))
        #expect(form.steps.count == 1)
        #expect(form.steps.first?.text == "")
    }
}
