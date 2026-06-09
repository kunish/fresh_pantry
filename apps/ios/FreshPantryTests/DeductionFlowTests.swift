import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for the cook → Deduction flow: the `DeductionController`
/// persistence seam (reduces stock, removes emptied rows, auto-logs CONSUMED
/// food-log departures) and the `DeductionReviewStore` select/skip/choose/amount
/// rules + atomic apply.
///
/// Backed by real in-memory `InventoryRepository` + `FoodLogRepository` so the
/// load → apply → persist → food-log path is exercised end-to-end through the
/// pure `ProposalApply.applyDeductionProposals` pipeline (identity re-resolution
/// preserved).
@MainActor
struct DeductionFlowTests {
    // MARK: Fixtures

    private func container() throws -> ModelContainer {
        try ModelContainerFactory.makeInMemory()
    }

    private func controller(_ container: ModelContainer) -> DeductionController {
        DeductionController(
            inventoryRepository: InventoryRepository(modelContainer: container),
            foodLogRepository: FoodLogRepository(modelContainer: container),
            householdID: "home"
        )
    }

    /// A numeric-stock inventory row. `state` lets a test stage freshness for the
    /// `wasExpiring` snapshot assertion.
    private func row(
        id: String,
        name: String,
        quantity: String,
        unit: String = "个",
        category: String = FoodCategories.other,
        state: FreshnessState = .fresh
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: quantity, unit: unit, imageUrl: "",
            freshnessPercent: state == .fresh ? 1.0 : 0.2, state: state,
            category: category, storage: .fridge, remoteVersion: 2
        )
    }

    /// A deduct proposal targeting a single inventory row by its live identity.
    private func deductProposal(
        id: String,
        ingredientName: String,
        amount: String,
        target: Ingredient,
        targetIndex: Int = 0
    ) -> DeductionProposal {
        let candidate = DeductionCandidate(
            inventoryRowIndex: targetIndex,
            displayLabel: "\(target.name) \(target.quantity)\(target.unit)",
            inventoryRowId: target.id,
            inventoryRowName: target.name,
            inventoryRowUnit: target.unit
        )
        return DeductionProposal(
            id: id,
            recipeIngredientName: ingredientName,
            requiredQty: "\(amount)\(target.unit)",
            candidates: [candidate],
            chosenIndex: targetIndex,
            deductAmount: amount
        )
    }

    // MARK: DeductionController — reduce a row's quantity

    @Test func controllerReducesRowQuantity() async throws {
        let container = try container()
        let inventory = InventoryRepository(modelContainer: container)
        let eggs = row(id: "ing_eggs", name: "鸡蛋", quantity: "10")
        try await inventory.saveItems("home", [eggs])

        let outcome = await controller(container).apply([
            deductProposal(id: "d0", ingredientName: "鸡蛋", amount: "3", target: eggs)
        ])

        #expect(outcome.persisted)
        #expect(outcome.reducedCount == 1)
        #expect(outcome.consumedCount == 0)

        let after = try await inventory.loadAllFor("home")
        #expect(after.count == 1)
        #expect(after[0].id == "ing_eggs") // same row, identity kept
        #expect(after[0].quantity == "7") // 10 - 3

        // A reduced (non-emptied) row logs NO departure.
        let log = try await FoodLogRepository(modelContainer: container).loadAllFor("home")
        #expect(log.isEmpty)
    }

    // MARK: DeductionController — empty a row + log consumed departure

    @Test func controllerRemovesEmptiedRowAndLogsConsumed() async throws {
        let container = try container()
        let inventory = InventoryRepository(modelContainer: container)
        // 紧急 (urgent) so wasExpiring must snapshot true.
        let salmon = row(id: "ing_salmon", name: "三文鱼", quantity: "1", unit: "盒",
                         category: FoodCategories.meatAndSeafood, state: .urgent)
        let rice = row(id: "ing_rice", name: "大米", quantity: "2", unit: "袋")
        try await inventory.saveItems("home", [salmon, rice])

        let outcome = await controller(container).apply([
            deductProposal(id: "d_salmon", ingredientName: "三文鱼", amount: "1", target: salmon, targetIndex: 0),
            deductProposal(id: "d_rice", ingredientName: "大米", amount: "1", target: rice, targetIndex: 1),
        ])

        #expect(outcome.persisted)
        #expect(outcome.consumedCount == 1) // salmon emptied
        #expect(outcome.reducedCount == 1)  // rice reduced

        let after = try await inventory.loadAllFor("home")
        #expect(after.map(\.id).sorted() == ["ing_rice"]) // salmon removed
        #expect(after.first(where: { $0.id == "ing_rice" })?.quantity == "1") // 2 - 1

        // The emptied salmon was logged as a CONSUMED departure that wasExpiring.
        let log = try await FoodLogRepository(modelContainer: container).loadAllFor("home")
        #expect(log.count == 1)
        let entry = try #require(log.first)
        #expect(entry.name == "三文鱼")
        #expect(entry.outcome == .consumed)
        #expect(entry.category == FoodCategories.meatAndSeafood)
        #expect(entry.wasExpiring) // urgent → not fresh → true
    }

    // MARK: wasExpiring snapshot — fresh row logs wasExpiring == false

    @Test func controllerConsumedFreshRowSnapshotsNotExpiring() async throws {
        let container = try container()
        let inventory = InventoryRepository(modelContainer: container)
        let milk = row(id: "ing_milk", name: "牛奶", quantity: "1", unit: "盒", state: .fresh)
        try await inventory.saveItems("home", [milk])

        _ = await controller(container).apply([
            deductProposal(id: "d_milk", ingredientName: "牛奶", amount: "1", target: milk)
        ])

        let log = try await FoodLogRepository(modelContainer: container).loadAllFor("home")
        #expect(log.count == 1)
        #expect(log.first?.wasExpiring == false) // fresh → false
    }

    // MARK: DeductionController — non-numeric stock left untouched, no log

    @Test func controllerLeavesNonNumericStockUntouched() async throws {
        let container = try container()
        let inventory = InventoryRepository(modelContainer: container)
        let salt = row(id: "ing_salt", name: "盐", quantity: "适量", unit: "")
        try await inventory.saveItems("home", [salt])

        let outcome = await controller(container).apply([
            deductProposal(id: "d_salt", ingredientName: "盐", amount: "1", target: salt)
        ])

        #expect(outcome.persisted)
        #expect(outcome.affectedCount == 0) // never coerced to 0 / deleted

        let after = try await inventory.loadAllFor("home")
        #expect(after.count == 1)
        #expect(after[0].quantity == "适量")
        let log = try await FoodLogRepository(modelContainer: container).loadAllFor("home")
        #expect(log.isEmpty)
    }

    // MARK: DeductionReviewStore — deductible / selected counts + 缺货 handling

    @Test func reviewStoreCountsOnlyDeductible() async throws {
        let container = try container()
        let eggs = row(id: "ing_eggs", name: "鸡蛋", quantity: "10")
        let store = makeStore(container, [
            deductProposal(id: "ok", ingredientName: "鸡蛋", amount: "2", target: eggs),
            DeductionProposal.empty(id: "missing", recipeIngredientName: "牛油果", requiredQty: "1个"),
        ])

        #expect(store.deductibleCount == 1) // the 缺货 row is never deductible
        #expect(store.selectedCount == 1)
        #expect(!store.hasNoDeductible)
        #expect(store.canConfirm)
    }

    @Test func reviewStoreAllMissingIsNotConfirmable() async throws {
        let container = try container()
        let store = makeStore(container, [
            DeductionProposal.empty(id: "m1", recipeIngredientName: "牛油果", requiredQty: "1个"),
            DeductionProposal.empty(id: "m2", recipeIngredientName: "罗勒", requiredQty: "适量"),
        ])
        #expect(store.hasNoDeductible)
        #expect(store.selectedCount == 0)
        #expect(!store.canConfirm)
    }

    // MARK: DeductionReviewStore — skip / re-select rules

    @Test func reviewStoreToggleActionDeductToSkipDeselects() async throws {
        let container = try container()
        let eggs = row(id: "ing_eggs", name: "鸡蛋", quantity: "10")
        let store = makeStore(container, [deductProposal(id: "e", ingredientName: "鸡蛋", amount: "2", target: eggs)])

        store.toggleAction("e") // deduct -> skip
        #expect(store.proposals[0].action == .skip)
        #expect(!store.proposals[0].selected)
        #expect(store.selectedCount == 0)

        store.toggleAction("e") // skip -> deduct (candidate exists) re-selects
        #expect(store.proposals[0].action == .deduct)
        #expect(store.proposals[0].selected)
        #expect(store.selectedCount == 1)
    }

    @Test func reviewStoreMissingRowCannotBeSelected() async throws {
        let container = try container()
        let store = makeStore(container, [
            DeductionProposal.empty(id: "m", recipeIngredientName: "牛油果", requiredQty: "1个"),
        ])
        store.toggleSelected("m") // a 缺货 row can never be selected
        #expect(!store.proposals[0].selected)
        // Toggling its action can't make it deductible either (no candidate).
        store.toggleAction("m")
        #expect(store.proposals[0].action == .skip)
        #expect(!store.proposals[0].selected)
    }

    // MARK: DeductionReviewStore — amount coercion (never 0)

    @Test func reviewStoreAmountCoercesNonPositiveToOne() async throws {
        let container = try container()
        let eggs = row(id: "ing_eggs", name: "鸡蛋", quantity: "10")
        let store = makeStore(container, [deductProposal(id: "e", ingredientName: "鸡蛋", amount: "2", target: eggs)])

        store.updateDeductAmount("e", "0")
        #expect(store.proposals[0].deductAmount == "1")
        store.updateDeductAmount("e", "适量")
        #expect(store.proposals[0].deductAmount == "1")
        store.updateDeductAmount("e", "4")
        #expect(store.proposals[0].deductAmount == "4")
    }

    // MARK: DeductionReviewStore — atomic apply of only deduct rows

    @Test func reviewStoreAppliesOnlyDeductRowsAtomically() async throws {
        let container = try container()
        let inventory = InventoryRepository(modelContainer: container)
        let eggs = row(id: "ing_eggs", name: "鸡蛋", quantity: "10")
        let milk = row(id: "ing_milk", name: "牛奶", quantity: "3", unit: "盒")
        try await inventory.saveItems("home", [eggs, milk])

        let store = makeStore(container, [
            deductProposal(id: "eggs", ingredientName: "鸡蛋", amount: "2", target: eggs, targetIndex: 0),
            deductProposal(id: "milk", ingredientName: "牛奶", amount: "1", target: milk, targetIndex: 1),
        ])
        store.toggleAction("milk") // skip the milk deduction

        let outcome = await store.apply()
        #expect(outcome.persisted)
        #expect(outcome.affectedCount == 1) // only eggs

        let after = try await inventory.loadAllFor("home")
        #expect(after.first(where: { $0.id == "ing_eggs" })?.quantity == "8") // 10 - 2
        #expect(after.first(where: { $0.id == "ing_milk" })?.quantity == "3") // untouched
    }

    // MARK: Helpers

    private func makeStore(_ container: ModelContainer, _ proposals: [DeductionProposal]) -> DeductionReviewStore {
        DeductionReviewStore(proposals: proposals, controller: controller(container))
    }
}
