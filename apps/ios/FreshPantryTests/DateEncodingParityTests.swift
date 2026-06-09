import Foundation
import Testing
@testable import FreshPantry

/// MealPlanEntry / FoodLogEntry date-encoding parity: yyyy-MM-dd vs ISO8601,
/// throw-on-dirty-date, local vs UTC normalization, outcome fallback.
struct DateEncodingParityTests {
    // MARK: MealPlanEntry

    @Test func mealPlanDateSerializedAsDateKey() throws {
        let date = MealPlanEntry.parseDate("2026-06-08")!
        let entry = MealPlanEntry(id: "mp_1", date: date, recipeId: "r1", recipeName: "番茄炒蛋")
        let json = try DomainJSON.encodeToString(entry)
        #expect(json.contains("\"date\":\"2026-06-08\"")) // NOT ISO
        #expect(!json.contains("T00:00:00")) // confirm no ISO timestamp leaked
    }

    @Test func mealPlanDateRoundTrip() throws {
        let date = MealPlanEntry.parseDate("2026-12-31")!
        let entry = MealPlanEntry(id: "mp_2", date: date, recipeId: "r2", recipeName: "饺子")
        let json = try DomainJSON.encodeToString(entry)
        let decoded = try DomainJSON.decode(MealPlanEntry.self, from: json)
        #expect(MealPlanEntry.dateKey(decoded.date) == "2026-12-31")
        #expect(decoded == entry) // identity by id
    }

    @Test func mealPlanDateNormalizedToLocalMidnight() {
        // An ISO timestamp with a time component must collapse to local midnight.
        let date = MealPlanEntry.parseDate("2026-06-08T15:30:00")!
        let normalized = MealPlanEntry.dateOnly(date)
        #expect(date == normalized)
        #expect(MealPlanEntry.dateKey(date) == "2026-06-08")
    }

    @Test func mealPlanThrowsOnMissingDate() {
        #expect(throws: (any Error).self) {
            try DomainJSON.decode(MealPlanEntry.self, from: #"{"id":"x","recipeId":"r"}"#)
        }
    }

    @Test func mealPlanThrowsOnUnparseableDate() {
        #expect(throws: (any Error).self) {
            try DomainJSON.decode(
                MealPlanEntry.self,
                from: #"{"id":"x","recipeId":"r","date":"not-a-date"}"#
            )
        }
    }

    @Test func mealPlanServingsDefault() throws {
        let entry = try DomainJSON.decode(
            MealPlanEntry.self,
            from: #"{"id":"x","recipeId":"r","recipeName":"n","date":"2026-01-01"}"#
        )
        #expect(entry.servings == 1)
        #expect(entry.done == false)
    }

    // MARK: FoodLogEntry

    @Test func foodLogLoggedAtSerializedISO8601UTC() throws {
        let loggedAt = JSONDate.parse("2026-06-08T10:15:00.000Z")!
        let entry = FoodLogEntry(id: "fl_1", name: "牛奶", outcome: .consumed, loggedAt: loggedAt)
        let json = try DomainJSON.encodeToString(entry)
        #expect(json.contains("\"loggedAt\":\"2026-06-08T10:15:00.000Z\""))
    }

    @Test func foodLogRoundTrip() throws {
        let loggedAt = JSONDate.parse("2026-06-08T10:15:00.000Z")!
        let entry = FoodLogEntry(
            id: "fl_2", name: "番茄", category: "果蔬生鲜", outcome: .wasted,
            loggedAt: loggedAt, wasExpiring: true, remoteVersion: 2
        )
        let json = try DomainJSON.encodeToString(entry)
        let decoded = try DomainJSON.decode(FoodLogEntry.self, from: json)
        #expect(decoded == entry)
        #expect(decoded.isWasted)
        #expect(decoded.loggedAt == loggedAt)
    }

    @Test func foodLogThrowsOnMissingLoggedAt() {
        #expect(throws: (any Error).self) {
            try DomainJSON.decode(FoodLogEntry.self, from: #"{"id":"fl","name":"x"}"#)
        }
    }

    @Test func foodLogOutcomeUnknownDefaultsToConsumed() throws {
        let entry = try DomainJSON.decode(
            FoodLogEntry.self,
            from: #"{"id":"fl","name":"x","outcome":"bogus","loggedAt":"2026-06-08T10:00:00Z"}"#
        )
        #expect(entry.outcome == .consumed)
    }

    @Test func foodLogOutcomeFromNameFallback() {
        #expect(FoodLogOutcome.fromName(nil) == .consumed)
        #expect(FoodLogOutcome.fromName("wasted") == .wasted)
        #expect(FoodLogOutcome.fromName("garbage") == .consumed)
    }

    @Test func foodLogNewIdPrefix() {
        #expect(FoodLogEntry.newId().hasPrefix("fl_"))
    }

    @Test func rescuedExpiringFlag() {
        let loggedAt = Date(timeIntervalSince1970: 0)
        let rescued = FoodLogEntry(id: "f", name: "x", outcome: .consumed,
                                   loggedAt: loggedAt, wasExpiring: true)
        #expect(rescued.rescuedExpiring)
        let wasted = FoodLogEntry(id: "g", name: "x", outcome: .wasted,
                                  loggedAt: loggedAt, wasExpiring: true)
        #expect(!wasted.rescuedExpiring)
    }
}
