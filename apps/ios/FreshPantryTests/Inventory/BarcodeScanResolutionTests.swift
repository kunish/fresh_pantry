import Foundation
import Testing
@testable import FreshPantry

/// Tests for the pure scan-resolution priority (`BarcodeScanResolution.decide`)
/// — local memory > OFF > manual, plus the invalid-barcode guard — and for the
/// local-memory branch of `AddIngredientForm.prefill(fromLocalName:…)`.
@MainActor
struct BarcodeScanResolutionTests {
    private func details(displayName: String = "OFF 牛奶") -> FoodDetails {
        FoodDetails(
            displayName: displayName,
            description: "测试",
            imageUrl: nil,
            category: FoodCategories.dairyAndEggs,
            storage: .fridge,
            shelfLifeDays: 7,
            source: "Open Food Facts",
            fetchedAt: Date()
        )
    }

    private func memory(name: String = "我的牛奶", category: String = FoodCategories.dairyAndEggs) -> BarcodeMemory {
        BarcodeMemory(barcode: "6901234567890", name: name, category: category, lastUsedAt: Date())
    }

    // MARK: Priority — local memory wins even when OFF also resolved

    @Test func localMemoryBeatsOpenFoodFacts() {
        let decision = BarcodeScanResolution.decide(
            barcode: "6901234567890",
            localMemory: memory(name: "我的牛奶", category: FoodCategories.dairyAndEggs),
            offDetails: details(displayName: "OFF 牛奶")
        )
        #expect(decision == .localMemory(name: "我的牛奶", category: FoodCategories.dairyAndEggs))
    }

    @Test func localMemoryCategoryIsCanonicalized() {
        let decision = BarcodeScanResolution.decide(
            barcode: "111",
            localMemory: memory(name: "酸奶", category: "乳制品"),
            offDetails: nil
        )
        #expect(decision == .localMemory(name: "酸奶", category: FoodCategories.dairyAndEggs))
    }

    // MARK: Priority — OFF used when no local memory

    @Test func openFoodFactsUsedWhenNoLocalMemory() {
        let off = details(displayName: "OFF 牛奶")
        let decision = BarcodeScanResolution.decide(barcode: "111", localMemory: nil, offDetails: off)
        #expect(decision == .openFoodFacts(off))
    }

    // MARK: Priority — neither source → manual fallback (no dead end)

    @Test func noHitFallsBackToManual() {
        let decision = BarcodeScanResolution.decide(barcode: "111", localMemory: nil, offDetails: nil)
        #expect(decision == .manualFallback)
    }

    // MARK: A blank-name memory row is not a usable hit → fall through

    @Test func blankNameMemoryFallsThroughToOpenFoodFacts() {
        let off = details(displayName: "OFF 牛奶")
        let decision = BarcodeScanResolution.decide(
            barcode: "111",
            localMemory: memory(name: "   "),
            offDetails: off
        )
        #expect(decision == .openFoodFacts(off))
    }

    // MARK: Invalid / empty barcode short-circuits

    @Test func blankBarcodeIsInvalid() {
        let decision = BarcodeScanResolution.decide(barcode: "   ", localMemory: memory(), offDetails: details())
        #expect(decision == .invalid)
    }

    // MARK: Local prefill mapping — name + category land, smart defaults fill the rest

    @Test func localPrefillSeedsNameCategoryAndBarcode() {
        let form = AddIngredientForm()
        form.prefill(fromLocalName: "三元鲜牛奶", category: FoodCategories.dairyAndEggs, barcode: "6901234567890")
        #expect(form.name == "三元鲜牛奶")
        #expect(form.category == FoodCategories.dairyAndEggs)
        #expect(form.barcode == "6901234567890")
        #expect(form.canSubmit)
    }

    @Test func localPrefillCategorySurvivesNameAutofill() {
        let form = AddIngredientForm()
        // Pin a deliberately off-knowledge category; a later name-commit autofill
        // must not stomp the learned category.
        form.prefill(fromLocalName: "牛奶", category: FoodCategories.other, barcode: "111")
        form.applySmartDefaults()
        #expect(form.category == FoodCategories.other)
    }

    @Test func localPrefillTrimsBarcodeToNilWhenBlank() {
        let form = AddIngredientForm()
        form.prefill(fromLocalName: "牛奶", category: FoodCategories.dairyAndEggs, barcode: "   ")
        #expect(form.barcode == nil)
    }
}
