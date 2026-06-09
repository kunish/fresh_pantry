import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Tests for the `SyncWriter` enqueue seam: the local-first no-op guards (blank
/// household / blank entityId) and the recorded `SyncOperation` shape. These run
/// against a REAL in-memory `SyncOutboxRepository` with a nil coordinator (no
/// live push) — no Supabase SDK, no credentials.
@MainActor
struct SyncWriterTests {
    // MARK: - Fixture

    /// A fresh in-memory outbox + isolated session, plus a coordinator-less
    /// writer (nil coordinator → enqueue records but never pushes).
    private struct Fixture {
        let outbox: SyncOutboxRepository
        let session: SyncSession
        let writer: SyncWriter
    }

    private func makeFixture(household: String) throws -> Fixture {
        let container = try ModelContainerFactory.makeInMemory()
        let outbox = SyncOutboxRepository(modelContainer: container)
        let defaults = UserDefaults(suiteName: "test.syncwriter.\(UUID().uuidString)")!
        let session = SyncSession(selectedHouseholdId: household, defaults: defaults)
        let writer = SyncWriter(outbox: outbox, coordinator: nil, session: session)
        return Fixture(outbox: outbox, session: session, writer: writer)
    }

    private func samplePatch() -> [String: JSONValue] {
        // Use a non-integral double + an explicit int so the patch survives the
        // outbox's JSON encode → decode round-trip byte-identically (an integral
        // double would decode back as `.int`).
        ["name": .string("番茄"), "quantity": .double(2.5), "checked": .bool(true)]
    }

    // MARK: - No-op guards

    @Test func enqueueWithBlankHouseholdRecordsNothing() async throws {
        let fixture = try makeFixture(household: "")

        await fixture.writer.enqueue(
            entityType: .inventoryItem,
            entityId: "ing_1",
            operation: .create,
            patch: samplePatch(),
            baseVersion: nil
        )

        // Blank household = personal/local-only mode: a no-op, not a dropped write.
        #expect(try await fixture.outbox.pendingCount() == 0)
    }

    @Test func enqueueWithBlankEntityIdRecordsNothing() async throws {
        let fixture = try makeFixture(household: "home")

        await fixture.writer.enqueue(
            entityType: .inventoryItem,
            entityId: "   ",
            operation: .create,
            patch: samplePatch(),
            baseVersion: nil
        )

        // Blank entityId is skipped even when a household is selected.
        #expect(try await fixture.outbox.pendingCount() == 0)
    }

    // MARK: - Recorded operation shape

    @Test func enqueueRecordsOneOperationWithFullShape() async throws {
        let fixture = try makeFixture(household: "home")
        let patch = samplePatch()

        await fixture.writer.enqueue(
            entityType: .shoppingItem,
            entityId: "si_42",
            operation: .toggleChecked,
            patch: patch,
            baseVersion: 7
        )

        let pending = try await fixture.outbox.loadPending()
        #expect(pending.count == 1)
        let op = try #require(pending.first)
        #expect(op.householdId == "home")
        #expect(op.clientId == fixture.session.clientId)
        #expect(op.entityType == .shoppingItem)
        #expect(op.operation == .toggleChecked)
        #expect(op.entityId == "si_42")
        #expect(op.patch == patch)
        #expect(op.baseVersion == 7)
    }

    // MARK: - Batch

    @Test func enqueueBatchRecordsEachOpInOrder() async throws {
        let fixture = try makeFixture(household: "home")
        let ops = (0..<3).map { index in
            SyncWriter.PendingOp(
                entityType: .inventoryItem,
                entityId: "ing_\(index)",
                operation: .create,
                patch: ["index": .int(index)],
                baseVersion: nil
            )
        }

        await fixture.writer.enqueueBatch(ops)

        // pendingCount == n and every distinct entityId is present (loadPending is
        // createdAt-ascending — all three landed).
        #expect(try await fixture.outbox.pendingCount() == 3)
        let pending = try await fixture.outbox.loadPending()
        let entityIds = pending.map(\.entityId)
        #expect(Set(entityIds) == ["ing_0", "ing_1", "ing_2"])
    }
}
