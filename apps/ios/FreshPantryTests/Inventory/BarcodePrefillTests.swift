import Foundation
import Testing
@testable import FreshPantry

/// Tests for the barcode → add-form prefill MAPPING (`AddIngredientForm.prefill`)
/// and the barcode carry-through onto the built proposal + resulting row. The
/// scanner UI / camera can't run in the simulator, so only the pure mapping is
/// exercised here (no `DataScannerViewController`, no network — a crafted
/// `FoodDetails` stands in for the OFF lookup result).
@MainActor
struct BarcodePrefillTests {
    private func details(
        displayName: String = "牛奶",
        category: String = FoodCategories.dairyAndEggs,
        storage: IconType = .fridge,
        shelfLifeDays: Int? = 7
    ) -> FoodDetails {
        FoodDetails(
            displayName: displayName,
            description: "测试",
            imageUrl: nil,
            category: category,
            storage: storage,
            shelfLifeDays: shelfLifeDays,
            source: "Open Food Facts",
            fetchedAt: Date()
        )
    }

    // MARK: Mapping — all fields land from the OFF details

    @Test func prefillMapsAllFieldsAndBarcode() {
        let form = AddIngredientForm()
        form.prefill(
            from: details(displayName: "鲜牛奶", category: FoodCategories.dairyAndEggs, storage: .fridge, shelfLifeDays: 5),
            barcode: "6901234567890"
        )

        #expect(form.name == "鲜牛奶")            // displayName → name
        #expect(form.category == FoodCategories.dairyAndEggs)
        #expect(form.storage == .fridge)
        #expect(form.shelfLifeDays == 5)
        #expect(form.barcode == "6901234567890")
    }

    // MARK: Mapping — OFF details pinned so a later name autofill can't stomp them

    @Test func prefilledFieldsSurviveSmartDefaults() {
        let form = AddIngredientForm()
        // OFF says pantry / 30 天 for a name that FoodKnowledge would map differently.
        form.prefill(
            from: details(displayName: "牛奶", category: FoodCategories.other, storage: .pantry, shelfLifeDays: 30),
            barcode: "111"
        )
        // A later name-commit autofill must NOT overwrite the OFF-pinned values.
        form.applySmartDefaults()
        #expect(form.category == FoodCategories.other)
        #expect(form.storage == .pantry)
        #expect(form.shelfLifeDays == 30)
    }

    // MARK: nil OFF result — still records the barcode, leaves name empty

    @Test func prefillWithNilDetailsKeepsOnlyBarcode() {
        let form = AddIngredientForm()
        form.prefill(from: nil, barcode: " 6901234567890 ")
        #expect(form.name == "")                  // nothing looked up
        #expect(form.barcode == "6901234567890")  // trimmed barcode recorded
        #expect(!form.canSubmit)                  // empty name → can't submit yet
    }

    // MARK: Barcode flows onto the built proposal → new inventory row

    @Test func barcodeFlowsOntoProposalAndRow() {
        let form = AddIngredientForm()
        form.prefill(from: details(displayName: "酸奶"), barcode: "6901234567890")
        form.quantity = "1"

        let proposal = form.buildProposal(inventory: [])
        #expect(proposal.name == "酸奶")
        #expect(proposal.barcode == "6901234567890")
        #expect(proposal.action == .newRow)

        // ProposalApply carries the barcode onto the resulting new row.
        let row = ProposalApply.ingredientFromProposal(proposal)
        #expect(row.barcode == "6901234567890")
        #expect(row.name == "酸奶")
    }

    // MARK: Blank barcode → nil (never an empty-string barcode on the row)

    @Test func blankBarcodeMapsToNil() {
        let form = AddIngredientForm()
        form.prefill(from: details(), barcode: "   ")
        #expect(form.barcode == nil)

        let proposal = form.buildProposal(inventory: [])
        #expect(proposal.barcode == nil)
        #expect(ProposalApply.ingredientFromProposal(proposal).barcode == nil)
    }
}
