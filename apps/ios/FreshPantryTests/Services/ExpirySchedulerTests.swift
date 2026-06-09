import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for the pure `ExpiryScheduler`: stable id hashing, the reserved
/// daily-summary id, [7,3,1] offset ordering, past-slot skipping, nil-expiry
/// skipping, and the 09:00-local scheduling. A fixed `now` + a fixed gregorian
/// calendar with an explicit time zone keep every assertion deterministic.
struct ExpirySchedulerTests {
    /// A fixed gregorian calendar pinned to a single time zone for determinism.
    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    /// `now` = 2026-06-09 08:00 local — before the daily 09:00 slot.
    private func now(_ cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 9; c.hour = 8; c.minute = 0
        return cal.date(from: c)!
    }

    /// A local date at midnight for a given y/m/d in the fixed calendar.
    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    private func ingredient(
        id: String = "ing-1",
        name: String = "牛奶",
        quantity: String = "2",
        unit: String = "盒",
        storage: IconType = .fridge,
        addedAt: Date? = nil,
        expiryDate: Date?
    ) -> Ingredient {
        Ingredient(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            imageUrl: "",
            freshnessPercent: 1.0,
            state: .fresh,
            storage: storage,
            expiryDate: expiryDate,
            addedAt: addedAt
        )
    }

    // MARK: id determinism + reserved-id avoidance

    @Test func idIsStableAcrossCalls() {
        let cal = calendar()
        let ing = ingredient(
            addedAt: date(cal, 2026, 6, 1),
            expiryDate: date(cal, 2026, 6, 20)
        )
        let first = ExpiryScheduler.idFor(ing, offset: 3)
        let second = ExpiryScheduler.idFor(ing, offset: 3)
        #expect(first == second)
        #expect(first > 0) // positive int31
        #expect(first <= 0x7fff_ffff)
    }

    @Test func differentOffsetsYieldDifferentIds() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let id1 = ExpiryScheduler.idFor(ing, offset: 1)
        let id3 = ExpiryScheduler.idFor(ing, offset: 3)
        let id7 = ExpiryScheduler.idFor(ing, offset: 7)
        #expect(Set([id1, id3, id7]).count == 3)
    }

    @Test func idNeverEqualsReservedDailySummaryId() {
        // Brute-force a population of ingredient field combinations; no per-item
        // id may collide with the reserved daily-summary id (1).
        let cal = calendar()
        for nameSeed in 0..<200 {
            let ing = ingredient(
                id: "ing-\(nameSeed)",
                name: "食材\(nameSeed)",
                expiryDate: date(cal, 2026, 6, 20)
            )
            for offset in [1, 3, 7] {
                #expect(ExpiryScheduler.idFor(ing, offset: offset) != ExpiryScheduler.dailySummaryId)
            }
        }
    }

    // MARK: offset ordering [7,3,1]

    @Test func enabledOffsetOrderPreservedInOutput() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 30))
        let settings = ReminderSettings(remindD1: true, remindD3: true, remindD7: true, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        // Expiry slots only (daily off). They are emitted largest-first: 7,3,1.
        let offsets = out.map { n -> Int in
            // 7 days before 6/30 = 6/23, 3 = 6/27, 1 = 6/29.
            let day = cal.component(.day, from: n.scheduledAt)
            switch day { case 23: return 7; case 27: return 3; case 29: return 1; default: return -1 }
        }
        #expect(offsets == [7, 3, 1])
    }

    // MARK: past-slot skipping

    @Test func allOffsetsInThePastYieldNoExpiryNotifications() {
        let cal = calendar()
        // Expiry yesterday → every D-N slot is already in the past.
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 8))
        let settings = ReminderSettings(remindD1: true, remindD3: true, remindD7: true, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.isEmpty)
    }

    // MARK: nil expiry

    @Test func nilExpiryIsSkipped() {
        let cal = calendar()
        let ing = ingredient(expiryDate: nil)
        let settings = ReminderSettings(remindD1: true, remindD3: true, remindD7: true, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.isEmpty)
    }

    // MARK: 09:00-local scheduling

    @Test func expirySlotIsOffsetDaysBeforeExpiryAt0900Local() {
        let cal = calendar()
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let settings = ReminderSettings(remindD1: false, remindD3: true, remindD7: false, remindDaily: false)
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        let slot = try! #require(out.first)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.scheduledAt)
        // 3 days before 6/20 = 6/17 at 09:00.
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 17)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
        #expect(slot.kind == .expiry)
        #expect(slot.title == "3 天后过期")
        #expect(slot.body == "牛奶 2盒 还剩 3 天")
    }

    // MARK: daily summary

    @Test func dailySummaryIsNextLocal0900WithReservedId() {
        let cal = calendar()
        let settings = ReminderSettings(remindD1: false, remindD3: false, remindD7: false, remindDaily: true)
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: now(cal), calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        #expect(summary.id == ExpiryScheduler.dailySummaryId)
        #expect(summary.id == 1)
        // now is 08:00 → today's 09:00 is still ahead → scheduled today at 09:00.
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: summary.scheduledAt)
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 9)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
    }

    @Test func dailySummaryRollsToTomorrowWhenPast0900() {
        let cal = calendar()
        // now = 2026-06-09 10:00 → past today's 09:00 → rolls to tomorrow.
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 9; c.hour = 10; c.minute = 0
        let lateNow = cal.date(from: c)!
        let settings = ReminderSettings(remindD1: false, remindD3: false, remindD7: false, remindDaily: true)
        let out = ExpiryScheduler.compute(
            inventory: [], settings: settings, now: lateNow, calendar: cal
        )
        let summary = try! #require(out.first { $0.kind == .dailySummary })
        let comps = cal.dateComponents([.day, .hour], from: summary.scheduledAt)
        #expect(comps.day == 10)
        #expect(comps.hour == 9)
    }

    @Test func dailySummaryOmittedWhenDisabled() {
        let cal = calendar()
        let settings = ReminderSettings(remindD1: true, remindD3: false, remindD7: false, remindDaily: false)
        let ing = ingredient(expiryDate: date(cal, 2026, 6, 20))
        let out = ExpiryScheduler.compute(
            inventory: [ing], settings: settings, now: now(cal), calendar: cal
        )
        #expect(out.allSatisfy { $0.kind == .expiry })
    }
}
