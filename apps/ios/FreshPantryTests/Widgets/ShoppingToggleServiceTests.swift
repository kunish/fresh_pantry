import Foundation
import SwiftData
import Testing
@testable import FreshPantry

@MainActor
struct ShoppingToggleServiceTests {
    private let hh = "hh-toggle"
    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    @Test func togglesCheckedAndRecordsOutboxOp() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let shopping = ShoppingRepository(modelContainer: container)
        try await shopping.upsert(hh, ShoppingItem(id: "x1", name: "牛奶", detail: "", category: FoodCategories.other, isChecked: false, remoteVersion: 3))

        let ok = await ShoppingToggleService.toggle(
            container: container, householdID: hh, itemID: "x1", clientID: "cli-1", now: now()
        )
        #expect(ok)

        // store 已翻转
        let after = try await shopping.loadAllFor(hh).first { $0.id == "x1" }
        #expect(after?.isChecked == true)

        // outbox 记了一条 .toggleChecked,baseVersion = 旧 remoteVersion(3)
        let outbox = SyncOutboxRepository(modelContainer: container)
        let ops = try await outbox.loadPending()
        #expect(ops.count == 1)
        #expect(ops.first?.entityType == .shoppingItem)
        #expect(ops.first?.operation == .toggleChecked)
        #expect(ops.first?.entityId == "x1")
        #expect(ops.first?.baseVersion == 3)
        #expect(ops.first?.clientId == "cli-1")
        if case .bool(let v)? = ops.first?.patch["isChecked"] { #expect(v == true) } else { Issue.record("patch 缺 isChecked") }
    }

    @Test func localOnlySkipsOutbox() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let shopping = ShoppingRepository(modelContainer: container)
        try await shopping.upsert("", ShoppingItem(id: "y1", name: "蛋", detail: "", category: FoodCategories.other, isChecked: false))

        // householdID 空 = 仅本地:翻转持久化,但不记 outbox(无远程)。
        let ok = await ShoppingToggleService.toggle(
            container: container, householdID: "", itemID: "y1", clientID: "cli-1", now: now()
        )
        #expect(ok)
        #expect((try await shopping.loadAllFor("").first { $0.id == "y1" })?.isChecked == true)
        #expect(try await SyncOutboxRepository(modelContainer: container).loadPending().isEmpty)
    }

    @Test func missingItemReturnsFalse() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let ok = await ShoppingToggleService.toggle(
            container: container, householdID: hh, itemID: "nope", clientID: "c", now: now()
        )
        #expect(!ok)
    }
}
