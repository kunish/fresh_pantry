import Foundation

/// DI seam for food-details lookups (mirrors the Dart `FoodDetailsClient`).
/// `Sendable` so it can cross the actor / store boundary; the concrete OFF impl
/// is stateless.
protocol FoodDetailsClient: Sendable {
    func lookup(_ ingredient: Ingredient) async throws -> FoodDetails?
}

/// Concrete client backed by `OpenFoodFactsService`. Mirrors the Dart
/// `OpenFoodFactsDetailsClient` — barcode-first, then name search. The OFF
/// service is best-effort (errors → nil internally), so this never throws in
/// practice, but the protocol keeps `throws` for an alternate backend.
struct OpenFoodFactsDetailsClient: FoodDetailsClient {
    func lookup(_ ingredient: Ingredient) async throws -> FoodDetails? {
        await OpenFoodFactsService.lookupDetails(
            name: ingredient.name,
            barcode: ingredient.barcode
        )
    }
}
