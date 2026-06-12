import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Tests for `SyncOutboxRepository.pendingEntityIDs()` — the read-only query that
/// powers the per-row 「待同步」 badge. Runs against a REAL in-memory outbox actor
/// (no Supabase). Covers multi-entity, dedup, empty, and post-ack-cleared cases.
@MainActor
struct SyncOutboxPendingEntityIDsTests {
    private func makeOutbox() throws -> SyncOutboxRepository {
        let container = try ModelContainerFactory.makeInMemory()
        return SyncOutboxRepository(modelContainer: container)
    }

    /// A minimal valid op for `entityId` under `entityType` (defaults to inventory).
    private func op(
        id: String = UUID().uuidString.lowercased(),
        entityId: String,
        entityType: SyncEntityType = .inventoryItem,
        operation: SyncOperationType = .create
    ) -> SyncOperation {
        SyncOperation(
            id: id,
            householdId: "home",
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            patch: ["name": .string("番茄")],
            clientId: "client-1",
            createdAt: Date()
        )
    }

    // MARK: Empty

    @Test func emptyOutboxReturnsEmptySet() async throws {
        let outbox = try makeOutbox()
        #expect(try await outbox.pendingEntityIDs().isEmpty)
    }

    // MARK: Multiple distinct entities

    @Test func returnsEveryDistinctPendingEntityID() async throws {
        let outbox = try makeOutbox()
        try await outbox.enqueue(op(entityId: "ing_1"))
        try await outbox.enqueue(op(entityId: "ing_2"))
        try await outbox.enqueue(op(entityId: "si_9", entityType: .shoppingItem))

        let pending = try await outbox.pendingEntityIDs()
        #expect(pending == ["ing_1", "ing_2", "si_9"])
    }

    // MARK: Dedup — multiple ops for one entity collapse to one membership

    @Test func multipleOpsForSameEntityDedupToOneID() async throws {
        let outbox = try makeOutbox()
        // Two DISTINCT outbox rows (different op ids) targeting the same entity —
        // e.g. a create then an update before either was acked.
        try await outbox.enqueue(op(id: "op-a", entityId: "ing_1", operation: .create))
        try await outbox.enqueue(op(id: "op-b", entityId: "ing_1", operation: .update))

        let pending = try await outbox.pendingEntityIDs()
        #expect(pending == ["ing_1"])
    }

    // MARK: Cleared after acknowledgement

    @Test func acknowledgingAllOpsClearsTheEntity() async throws {
        let outbox = try makeOutbox()
        try await outbox.enqueue(op(id: "op-a", entityId: "ing_1", operation: .create))
        try await outbox.enqueue(op(id: "op-b", entityId: "ing_1", operation: .update))
        #expect(try await outbox.pendingEntityIDs() == ["ing_1"])

        // Ack only one of the two rows — the entity is STILL pending.
        try await outbox.removeAcknowledged(["op-a"])
        #expect(try await outbox.pendingEntityIDs() == ["ing_1"])

        // Ack the last row — the entity drops out of the pending set.
        try await outbox.removeAcknowledged(["op-b"])
        #expect(try await outbox.pendingEntityIDs().isEmpty)
    }
}
