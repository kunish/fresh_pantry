import Foundation
import Testing
@testable import FreshPantry

/// Pure-logic tests for the App Intents support layer: shopping-name
/// normalization, the pending-add queue (FIFO + drain-once), and the
/// expiring-food selector (N-day window using the canonical `ExpiryCalculator`).
/// No AppIntents runtime, no Siri — only the testable seams.
struct IntentSupportTests {
    // MARK: - IntentName

    @Test func normalizeTrimsSurroundingWhitespace() {
        #expect(IntentName.normalize("  牛奶  ") == "牛奶")
    }

    @Test func normalizeRejectsBlank() {
        #expect(IntentName.normalize("") == nil)
        #expect(IntentName.normalize("   ") == nil)
        #expect(IntentName.normalize("\n\t") == nil)
    }

    // MARK: - IntentPendingAddQueue

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.intent.queue.\(UUID().uuidString)")!
    }

    @Test func queueEnqueuesInOrderAndPeekDoesNotClear() {
        let queue = IntentPendingAddQueue(defaults: isolatedDefaults())
        queue.enqueue("牛奶")
        queue.enqueue("鸡蛋")
        #expect(queue.peek() == ["牛奶", "鸡蛋"])
        // Peek must be non-destructive.
        #expect(queue.peek() == ["牛奶", "鸡蛋"])
    }

    @Test func queueDrainReturnsAllThenClears() {
        let queue = IntentPendingAddQueue(defaults: isolatedDefaults())
        queue.enqueue("牛奶")
        queue.enqueue("鸡蛋")
        #expect(queue.drainAll() == ["牛奶", "鸡蛋"])
        // Drained exactly once — a second drain is empty.
        #expect(queue.drainAll() == [])
        #expect(queue.peek() == [])
    }

    @Test func queueDrainOnEmptyIsNoOp() {
        let queue = IntentPendingAddQueue(defaults: isolatedDefaults())
        #expect(queue.drainAll() == [])
    }

    @Test func queueRemoveTakesOnlyTheNamedConsumedEntries() {
        // The "ack on success" path: a name that failed to persist stays queued
        // for the next foreground retry; only the consumed names are removed.
        let queue = IntentPendingAddQueue(defaults: isolatedDefaults())
        queue.enqueue("牛奶")
        queue.enqueue("鸡蛋")
        queue.enqueue("面包")
        queue.remove(["牛奶", "面包"]) // 鸡蛋's add failed → keep it
        #expect(queue.peek() == ["鸡蛋"])
    }

    @Test func queueRemoveOfAllClearsTheQueue() {
        let queue = IntentPendingAddQueue(defaults: isolatedDefaults())
        queue.enqueue("牛奶")
        queue.remove(["牛奶"])
        #expect(queue.peek() == [])
    }

    @Test func queueRemoveDropsOneOccurrencePerName() {
        // Duplicate enqueues remove one-for-one, so a still-pending duplicate isn't
        // wiped by a single consume.
        let queue = IntentPendingAddQueue(defaults: isolatedDefaults())
        queue.enqueue("牛奶")
        queue.enqueue("牛奶")
        queue.remove(["牛奶"])
        #expect(queue.peek() == ["牛奶"])
    }

    // MARK: - ExpiringFoodSelector

    private func item(_ name: String, expiresInDays days: Int?, now: Date) -> Ingredient {
        let expiry = days.map { Calendar.current.date(byAdding: .day, value: $0, to: now)! }
        return Ingredient(
            id: name, name: name, quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, category: FoodCategories.other,
            storage: .fridge, expiryDate: expiry
        )
    }

    @Test func selectorIncludesWithinWindowSoonestFirst() {
        let now = Date()
        let items = [
            item("牛奶", expiresInDays: 3, now: now),
            item("鸡蛋", expiresInDays: 1, now: now),
            item("酸奶", expiresInDays: 2, now: now),
        ]
        #expect(ExpiringFoodSelector.expiringNames(in: items, withinDays: 3, now: now)
            == ["鸡蛋", "酸奶", "牛奶"])
    }

    @Test func selectorExcludesBeyondWindowAndNoExpiry() {
        let now = Date()
        let items = [
            item("牛奶", expiresInDays: 3, now: now),
            item("大米", expiresInDays: nil, now: now),   // no expiry → excluded
            item("罐头", expiresInDays: 10, now: now),     // beyond window → excluded
        ]
        #expect(ExpiringFoodSelector.expiringNames(in: items, withinDays: 3, now: now) == ["牛奶"])
    }

    @Test func selectorIncludesAlreadyExpired() {
        let now = Date()
        let items = [
            item("菠菜", expiresInDays: -2, now: now),     // already expired → most urgent
            item("牛奶", expiresInDays: 1, now: now),
        ]
        #expect(ExpiringFoodSelector.expiringNames(in: items, withinDays: 3, now: now)
            == ["菠菜", "牛奶"])
    }

    @Test func selectorDefaultWindowIsThreeDays() {
        #expect(ExpiringFoodSelector.defaultWithinDays == 3)
        let now = Date()
        let items = [
            item("牛奶", expiresInDays: 3, now: now),  // inside default window
            item("罐头", expiresInDays: 4, now: now),  // outside default window
        ]
        #expect(ExpiringFoodSelector.expiringNames(in: items, now: now) == ["牛奶"])
    }
}
