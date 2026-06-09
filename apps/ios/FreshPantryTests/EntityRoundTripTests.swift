import Foundation
import Testing
@testable import FreshPantry

/// JSON round-trip + defaults for ShoppingItem, Recipe/RecipeIngredient,
/// FoodLogEntry, FoodDetails, AiSettings, ReminderSettings, StorageArea.
struct EntityRoundTripTests {
    // MARK: ShoppingItem

    @Test func shoppingItemDefaultsAndRoundTrip() throws {
        let decoded = try DomainJSON.decode(ShoppingItem.self, from: #"{"name":"牛奶"}"#)
        #expect(decoded.id == "")
        #expect(decoded.detail == "")
        #expect(decoded.category == FoodCategories.other)
        #expect(decoded.isChecked == false)
        #expect(decoded.imageUrl == nil)

        let item = ShoppingItem(
            id: "si_1", name: "鸡蛋", detail: "12 个", imageUrl: "x",
            category: "乳品蛋类", isChecked: true, remoteVersion: 3
        )
        let json = try DomainJSON.encodeToString(item)
        #expect(try DomainJSON.decode(ShoppingItem.self, from: json) == item)
    }

    @Test func shoppingItemNewIdIsUuid() {
        // Sync-clean: a freshly minted shopping id is a UUID, so the household
        // sync engine reconciles it by id remotely without duplicating.
        #expect(ProposalApply.isUuid(ShoppingItem.newId()))
    }

    @Test func shoppingItemFromIngredient() {
        let ingredient = Ingredient(
            name: "番茄", quantity: "3", unit: "个", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: "果蔬生鲜"
        )
        let item = ShoppingItem.fromIngredient(ingredient, id: "si_x")
        #expect(item.detail == "3 个")
        #expect(item.imageUrl == nil) // empty imageUrl -> nil
        #expect(item.category == "果蔬生鲜")
    }

    @Test func shoppingItemFromIngredientCategoryFallback() {
        let ingredient = Ingredient(
            name: "x", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: nil
        )
        #expect(ShoppingItem.fromIngredient(ingredient).category == FoodCategories.other)
    }

    // MARK: Recipe

    @Test func recipeDefaults() throws {
        let recipe = try DomainJSON.decode(Recipe.self, from: #"{"name":"汤"}"#)
        #expect(recipe.difficulty == 0)
        #expect(recipe.cookingMinutes == 30) // default differs from difficulty
        #expect(recipe.tags.isEmpty)
        #expect(recipe.ingredients.isEmpty)
    }

    @Test func recipeRoundTrip() throws {
        let recipe = Recipe(
            id: "r_1", name: "番茄炒蛋", category: "家常", difficulty: 2,
            cookingMinutes: 15, description: "经典",
            ingredients: [
                RecipeIngredient(name: "番茄", quantity: "2", unit: "个"),
                RecipeIngredient(name: "鸡蛋", quantity: "3", unit: "个"),
            ],
            steps: ["切番茄", "打蛋"], tags: ["快手"], imageUrl: "x", remoteVersion: 1
        )
        let json = try DomainJSON.encodeToString(recipe)
        let decoded = try DomainJSON.decode(Recipe.self, from: json)
        #expect(decoded == recipe) // identity by id
        #expect(decoded.ingredients.count == 2)
        #expect(decoded.ingredients[0].amount == "2个")
    }

    @Test func difficultyLabel() {
        func recipe(_ d: Int) -> Recipe {
            Recipe(id: "x", name: "n", category: "", difficulty: d,
                   cookingMinutes: 30, description: "", ingredients: [], steps: [])
        }
        #expect(recipe(0).difficultyLabel == "难度未设置")
        #expect(recipe(-1).difficultyLabel == "难度未设置")
        #expect(recipe(3).difficultyLabel == "难度 3/5")
        #expect(recipe(9).difficultyLabel == "难度 5/5") // clamp to 5
    }

    @Test func recipeIngredientLegacyAmountParse() throws {
        // Legacy shape: only `amount` key, no quantity/unit.
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self, from: #"{"name":"盐","amount":"3 克"}"#
        )
        #expect(decoded.quantity == "3")
        #expect(decoded.unit == "克")
        #expect(decoded.amount == "3 克") // original amount preserved
    }

    @Test func recipeIngredientLegacyNonNumericAmount() throws {
        let decoded = try DomainJSON.decode(
            RecipeIngredient.self, from: #"{"name":"盐","amount":"适量"}"#
        )
        #expect(decoded.quantity == "")
        #expect(decoded.unit == "适量") // all goes to unit when no leading number
    }

    @Test func recipeIngredientNewShapeComposesAmount() {
        let ingredient = RecipeIngredient(name: "糖", quantity: "10", unit: "g")
        #expect(ingredient.amount == "10g")
    }

    @Test func recipeIngredientScaledBy() {
        let ingredient = RecipeIngredient(name: "糖", quantity: "10", unit: "g")
        #expect(ingredient.scaledBy(2).quantity == "20")
        #expect(ingredient.scaledBy(1) == ingredient) // factor==1 no-op
        let nonNumeric = RecipeIngredient(name: "盐", quantity: "适量", unit: "")
        #expect(nonNumeric.scaledBy(3) == nonNumeric) // non-numeric unchanged
    }

    // MARK: FoodDetails

    @Test func foodDetailsWritesCacheVersion5() throws {
        let details = FoodDetails(
            displayName: "牛奶", description: "d", imageUrl: nil, category: "乳品蛋类",
            storage: .fridge, shelfLifeDays: 7, source: "off",
            fetchedAt: Date(timeIntervalSince1970: 1000),
            nutrition: NutritionFacts(energyKcal: 42)
        )
        let json = try DomainJSON.encodeToString(details)
        #expect(json.contains("\"cacheVersion\":5"))
        let decoded = try DomainJSON.decode(FoodDetails.self, from: json)
        #expect(decoded.nutrition?.energyKcal == 42)
    }

    @Test func foodDetailsFetchedAtEpochFallback() throws {
        let decoded = try DomainJSON.decode(FoodDetails.self, from: #"{"displayName":"x"}"#)
        #expect(decoded.fetchedAt == Date(timeIntervalSince1970: 0))
    }

    @Test func nutritionFromOffNutriments() {
        let facts = NutritionFacts.fromOffNutriments([
            "energy-kcal_100g": 52,
            "proteins_100g": "0.3",
        ])
        #expect(facts?.energyKcal == 52)
        #expect(facts?.protein == 0.3)
        #expect(NutritionFacts.fromOffNutriments([:]) == nil) // empty -> nil
    }

    // MARK: AiSettings / ReminderSettings / StorageArea

    @Test func aiSettingsTimeoutSeconds() throws {
        let settings = AiSettings(baseUrl: "u", apiKey: "k", model: "m", timeout: 90)
        let json = try DomainJSON.encodeToString(settings)
        #expect(json.contains("\"timeoutSeconds\":90"))
        #expect(try DomainJSON.decode(AiSettings.self, from: json).timeout == 90)
        #expect(AiSettings.empty.isConfigured == false)
        #expect(settings.isConfigured == true)
    }

    @Test func aiSettingsDefaultTimeout() throws {
        let decoded = try DomainJSON.decode(AiSettings.self, from: #"{"baseUrl":"u"}"#)
        #expect(decoded.timeout == 60)
    }

    @Test func reminderSettingsDefaultsAndOffsets() throws {
        let decoded = try DomainJSON.decode(ReminderSettings.self, from: "{}")
        #expect(decoded.remindD1 == true)
        #expect(decoded.remindD3 == true)
        #expect(decoded.remindD7 == false)
        #expect(decoded.remindDaily == true)
        #expect(decoded.enabledOffsetDays == [3, 1]) // largest-first, D7 off
    }

    @Test func storageAreaRoundTrip() throws {
        let area = StorageArea(name: "冰箱", icon: .fridge, itemCount: 5, capacityPercent: 0.5)
        let json = try DomainJSON.encodeToString(area)
        #expect(json.contains("\"icon\":\"fridge\""))
        #expect(try DomainJSON.decode(StorageArea.self, from: json) == area)
    }
}
