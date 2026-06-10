import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Behavior tests for shopping-list quantity editing: the duplicate-name add
/// that auto-merges same-unit quantities (同名自动聚合) and the free-text
/// `updateDetail` mutation. Backed by a real in-memory repository so the
/// name-unique persist path is exercised end-to-end, and a real outbox so the
/// sync enqueue contract is asserted (a silent local-only write would never
/// reach other household members).
@MainActor
struct ShoppingQuantityEditTests {
    private func makeStore(_ items: [ShoppingItem], household: String = "home") async throws -> ShoppingStore {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let store = ShoppingStore(repository: repo, householdID: household)
        await store.load()
        return store
    }

    /// Store wired to a real outbox (same pattern as
    /// `ShoppingStoreTests.deleteEnqueuesSoftDeleteSyncOp`).
    private func makeSyncedStore(
        _ items: [ShoppingItem],
        household: String = "home"
    ) async throws -> (store: ShoppingStore, outbox: SyncOutboxRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let repo = ShoppingRepository(modelContainer: container)
        try await repo.saveItems(household, items)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let session = SyncSession(
            selectedHouseholdId: household,
            defaults: UserDefaults(suiteName: "test.shopping.quantity.\(UUID().uuidString)")!
        )
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        let store = ShoppingStore(repository: repo, householdID: household, syncWriter: writer)
        await store.load()
        return (store, outbox)
    }

    private func item(
        id: String = ShoppingItem.newId(),
        name: String,
        detail: String = "",
        category: String = FoodCategories.other,
        remoteVersion: Int = 0
    ) -> ShoppingItem {
        ShoppingItem(id: id, name: name, detail: detail, category: category, remoteVersion: remoteVersion)
    }

    // MARK: Duplicate-name add → quantity merge

    @Test func addMergesSameUnitIntegerQuantities() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", detail: "2 个")])
        let merged = await store.add(name: "牛奶", detail: "3 个")
        #expect(merged)
        #expect(store.items.count == 1)
        #expect(store.items.first?.detail == "5 个")
        #expect(store.items.first?.id == "a") // existing row updated, never re-minted
    }

    @Test func addMergesDecimalQuantitiesWithoutFloatNoise() async throws {
        // 1.1 + 2.2 is 3.3000000000000003 in binary floats; the stored detail
        // must come out of `QuantityText.formatQuantity` clean.
        let store = try await makeStore([item(id: "a", name: "牛肉", detail: "1.1 kg")])
        let merged = await store.add(name: "牛肉", detail: "2.2 kg")
        #expect(merged)
        #expect(store.items.first?.detail == "3.3 kg")
    }

    @Test func addMergeToleratesUnitCaseAndWhitespace() async throws {
        // Unit comparison is trimmed + case-insensitive; the existing row's
        // unit spelling wins (we're updating that row).
        let store = try await makeStore([item(id: "a", name: "面粉", detail: "2 KG")])
        let merged = await store.add(name: " 面粉 ", detail: "  3kg  ")
        #expect(merged)
        #expect(store.items.count == 1)
        #expect(store.items.first?.detail == "5 KG")
    }

    @Test func addUnitMismatchKeepsDuplicateRejection() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", detail: "2 个")])
        let merged = await store.add(name: "牛奶", detail: "3 盒")
        #expect(!merged)
        #expect(store.items.count == 1)
        #expect(store.items.first?.detail == "2 个") // existing row untouched
    }

    @Test func addBlankDetailKeepsDuplicateRejection() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", detail: "2 个")])
        let merged = await store.add(name: "牛奶", detail: "   ")
        #expect(!merged)
        #expect(store.items.count == 1)
        #expect(store.items.first?.detail == "2 个")
    }

    @Test func addUnparseableExistingDetailKeepsDuplicateRejection() async throws {
        // Free-text existing detail ("适量") has no leading number — never guess.
        let store = try await makeStore([item(id: "a", name: "盐", detail: "适量")])
        let merged = await store.add(name: "盐", detail: "2 包")
        #expect(!merged)
        #expect(store.items.first?.detail == "适量")
    }

    @Test func mergedAddPersistsAndKeepsNameUnique() async throws {
        let store = try await makeStore([item(id: "a", name: "鸡蛋", detail: "6 个")])
        #expect(await store.add(name: "鸡蛋", detail: "6 个"))

        // Survives the repo's normalize + name-dedup reload: still one row.
        await store.load()
        #expect(store.items.count == 1)
        #expect(store.items.first?.detail == "12 个")
    }

    @Test func mergedAddEnqueuesFullRowUpdate() async throws {
        let uuid = UUID().uuidString.lowercased()
        let (store, outbox) = try await makeSyncedStore([
            item(id: uuid, name: "牛奶", detail: "2 个", remoteVersion: 4)
        ])

        #expect(await store.add(name: "牛奶", detail: "3 个"))

        let pending = try await outbox.loadPending()
        #expect(pending.count == 1)
        let op = try #require(pending.first)
        #expect(op.entityType == .shoppingItem)
        #expect(op.operation == .update)
        #expect(op.entityId == uuid)
        #expect(op.baseVersion == 4)
        #expect(op.patch["detail"] == .string("5 个"))
    }

    @Test func addMergeIntoCheckedRowFlipsBackToUnchecked() async throws {
        // Re-adding means "need to buy again": merging into a checked (已购)
        // row must flip it back to unchecked, or the merged quantity hides in
        // the 已购 bucket (invisible under the 待购 filter) and later inflates
        // the 入库 amount.
        let (store, outbox) = try await makeSyncedStore([
            ShoppingItem(
                id: "a", name: "牛奶", detail: "2 个",
                category: FoodCategories.other, isChecked: true, remoteVersion: 4
            )
        ])

        #expect(await store.add(name: "牛奶", detail: "3 个"))

        let row = store.items.first { $0.id == "a" }
        #expect(row?.detail == "5 个")
        #expect(row?.isChecked == false)

        let op = try #require(try await outbox.loadPending().first)
        #expect(op.patch["isChecked"] == .bool(false))
    }

    // MARK: updateDetail

    @Test func updateDetailRewritesDetailAndPersists() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", detail: "2 盒")])
        let target = store.items.first { $0.id == "a" }!

        let updated = await store.updateDetail(target, detail: "5 盒")
        #expect(updated)
        #expect(store.items.first { $0.id == "a" }?.detail == "5 盒")

        // Survives a reload (persisted, not just local mutation).
        await store.load()
        #expect(store.items.first { $0.id == "a" }?.detail == "5 盒")
    }

    @Test func updateDetailAllowsClearing() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", detail: "2 盒")])
        let target = store.items.first { $0.id == "a" }!

        #expect(await store.updateDetail(target, detail: ""))
        #expect(store.items.first { $0.id == "a" }?.detail == "")
        await store.load()
        #expect(store.items.first { $0.id == "a" }?.detail == "")
    }

    @Test func updateDetailUnknownItemReturnsFalse() async throws {
        let store = try await makeStore([item(id: "a", name: "牛奶", detail: "2 盒")])
        let ghost = item(id: "zzz", name: "幽灵")
        #expect(!(await store.updateDetail(ghost, detail: "1 个")))
        #expect(store.items.first { $0.id == "a" }?.detail == "2 盒")
    }

    @Test func updateDetailEnqueuesUpdateOp() async throws {
        let uuid = UUID().uuidString.lowercased()
        let (store, outbox) = try await makeSyncedStore([
            item(id: uuid, name: "牛奶", detail: "2 盒", remoteVersion: 7)
        ])
        let target = store.items.first { $0.id == uuid }!

        #expect(await store.updateDetail(target, detail: "3 盒"))

        let pending = try await outbox.loadPending()
        #expect(pending.count == 1)
        let op = try #require(pending.first)
        #expect(op.entityType == .shoppingItem)
        #expect(op.operation == .update)
        #expect(op.entityId == uuid)
        #expect(op.baseVersion == 7)
        #expect(op.patch["detail"] == .string("3 盒"))
    }
}
