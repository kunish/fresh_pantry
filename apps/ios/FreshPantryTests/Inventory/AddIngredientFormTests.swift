import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for `AddIngredientForm.prefillExpiry` — the seam that turns an
/// absolute expiry `Date` recognized off a packaging photo into the form's
/// days-from-now shelf-life. Covers the day-count conversion, the past-date guard,
/// and that the prefilled value is pinned as user-edited so a later name-commit
/// autofill can't stomp it. `now` is injected for deterministic day math.
@MainActor
struct AddIngredientFormTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return calendar.date(from: c)!
    }

    // MARK: prefillExpiry — converts an absolute date to whole days from now

    @Test func prefillExpirySetsShelfLifeFromDayDifference() {
        let form = AddIngredientForm()
        let now = at(2026, 1, 1)
        let result = form.prefillExpiry(date: at(2026, 1, 31), now: now)
        #expect(result == 30)
        #expect(form.shelfLifeDays == 30)
    }

    // MARK: prefillExpiry — a past / today date is refused (no 0/negative shelf life)

    @Test func prefillExpiryRejectsPastDate() {
        let form = AddIngredientForm()
        let now = at(2026, 6, 1)
        #expect(form.prefillExpiry(date: at(2026, 5, 1), now: now) == nil)
        // Shelf-life is left untouched (no silent 0/negative value).
        #expect(form.shelfLifeDays == nil)
    }

    @Test func prefillExpiryRejectsToday() {
        let form = AddIngredientForm()
        let now = at(2026, 6, 1)
        #expect(form.prefillExpiry(date: at(2026, 6, 1), now: now) == nil)
        #expect(form.shelfLifeDays == nil)
    }

    // MARK: prefillExpiry — pins the value so a later name-commit autofill can't stomp it

    @Test func prefillExpiryPinsShelfLifeAgainstSmartDefaults() {
        let form = AddIngredientForm()
        let now = at(2026, 1, 1)
        form.prefillExpiry(date: at(2026, 1, 11), now: now) // 10 days
        #expect(form.shelfLifeDays == 10)

        // A name commit would normally apply FoodKnowledge shelf-life defaults; the
        // scanned shelf-life must survive (setShelfLife marks the field edited).
        form.name = "牛奶"
        form.applySmartDefaults()
        #expect(form.shelfLifeDays == 10)
    }
}
