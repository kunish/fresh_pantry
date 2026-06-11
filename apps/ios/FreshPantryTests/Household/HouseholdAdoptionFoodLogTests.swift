import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// The createHousehold adoption must move the personal (`""` scope) FoodLog
/// history into the new household scope and purge `""` — otherwise the waste
/// stats clear to zero the moment a household is created, and the stranded
/// history never uploads (`uploadLocalOnly` only reads the household scope).
/// Non-UUID `fl_…` ids are re-minted so the rows can land in the Supabase uuid
/// PK column (matching the other four adopted entity types).
@MainActor
struct HouseholdAdoptionFoodLogTests {
    /// Store with real in-memory repos and no backend (the
    /// `HouseholdSessionStoreTests` pattern). The food-log repo is built on the
    /// SAME container the inventory repo uses — exactly how adoption derives its
    /// own handle in production (all repos share the one app container).
    private func makeStore() throws -> (store: HouseholdSessionStore, foodLog: FoodLogRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let foodLog = FoodLogRepository(modelContainer: container)
        let store = HouseholdSessionStore(
            remote: nil,
            session: SyncSession(selectedHouseholdId: ""),
            auth: AuthService(backend: nil),
            inventory: InventoryRepository(modelContainer: container),
            shopping: ShoppingRepository(modelContainer: container),
            customRecipe: CustomRecipeRepository(modelContainer: container),
            mealPlan: MealPlanRepository(modelContainer: container)
        )
        return (store, foodLog)
    }

    private func entry(id: String, name: String) -> FoodLogEntry {
        FoodLogEntry(id: id, name: name, outcome: .consumed, loggedAt: Date())
    }

    private let uuid = "11111111-1111-4111-8111-111111111111"

    @Test func adoptMovesFoodLogIntoHouseholdAndClearsLocal() async throws {
        let (store, foodLog) = try makeStore()
        try await foodLog.append("", entry(id: uuid, name: "牛奶"))
        try await foodLog.append("", entry(id: "fl_12345", name: "鸡蛋"))

        await store.adoptLocalDataIntoHousehold("home")

        // Moved into the household scope; the personal scope is purged.
        let moved = try await foodLog.loadAllFor("home")
        #expect(moved.count == 2)
        #expect(try await foodLog.loadAllFor("").isEmpty)

        // The valid UUID survives unchanged; the legacy `fl_…` id is re-minted.
        let movedIds = Set(moved.map(\.id))
        #expect(movedIds.contains(uuid))
        #expect(!movedIds.contains("fl_12345"))
        #expect(moved.allSatisfy { ProposalApply.isUuid($0.id) })
        // Payload (not just the row) survives the move.
        #expect(Set(moved.map(\.name)) == ["牛奶", "鸡蛋"])
    }

    @Test func adoptIntoEmptyIdLeavesFoodLogUntouched() async throws {
        let (store, foodLog) = try makeStore()
        try await foodLog.append("", entry(id: uuid, name: "牛奶"))

        // Empty id must never purge the personal scope (guard mirrors the other
        // adopted entity types).
        await store.adoptLocalDataIntoHousehold("")

        #expect(try await foodLog.loadAllFor("").count == 1)
    }

    @Test func adoptWithNoFoodLogIsNoOp() async throws {
        let (store, foodLog) = try makeStore()
        await store.adoptLocalDataIntoHousehold("home")
        #expect(try await foodLog.loadAllFor("home").isEmpty)
    }
}
