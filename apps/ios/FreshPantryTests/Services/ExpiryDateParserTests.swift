import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for the PURE expiry-date extraction (`ExpiryDateParser`) behind the
/// on-device OCR. The Vision step is not tested (it needs the engine + a real
/// image); only the deterministic text → `Date?` parsing is covered — formats,
/// candidate selection, the production-date + duration derivation, and the
/// noise/false-positive guards. `now` is injected so the duration math is stable.
struct ExpiryDateParserTests {
    /// Gregorian, local-tz calendar matching the parser's, for asserting on the
    /// returned date-only values.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return calendar.date(from: c)!
    }

    /// Year/month/day triple as an Equatable nominal type — a bare tuple can't be
    /// compared through `Optional` (`(Int,Int,Int)?` has no `==`).
    private struct YMD: Equatable { let y: Int, m: Int, d: Int }

    private func components(_ date: Date?) -> YMD? {
        guard let date else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return YMD(y: c.year!, m: c.month!, d: c.day!)
    }

    // MARK: Numeric formats — YYYY-MM-DD / YYYY/MM/DD / YYYY.MM.DD

    @Test func parsesDashedDate() {
        #expect(components(ExpiryDateParser.parse("2026-05-01")) == YMD(y: 2026, m: 5, d: 1))
    }

    @Test func parsesSlashedDate() {
        #expect(components(ExpiryDateParser.parse("2026/05/01")) == YMD(y: 2026, m: 5, d: 1))
    }

    @Test func parsesDottedDate() {
        #expect(components(ExpiryDateParser.parse("2026.05.01")) == YMD(y: 2026, m: 5, d: 1))
    }

    @Test func parsesCompactEightDigitDate() {
        #expect(components(ExpiryDateParser.parse("20260501")) == YMD(y: 2026, m: 5, d: 1))
    }

    // MARK: Chinese 年月日

    @Test func parsesChineseYearMonthDay() {
        #expect(components(ExpiryDateParser.parse("2026年05月01日")) == YMD(y: 2026, m: 5, d: 1))
    }

    @Test func parsesChineseYearMonthOnlyDefaultsToFirst() {
        // No day component → default to the 1st of the month.
        #expect(components(ExpiryDateParser.parse("2026年05月")) == YMD(y: 2026, m: 5, d: 1))
    }

    @Test func parsesFullWidthDigits() {
        // OCR sometimes emits full-width digits — normalize then parse.
        #expect(components(ExpiryDateParser.parse("２０２６年０５月０１日")) == YMD(y: 2026, m: 5, d: 1))
    }

    // MARK: Explicit expiry labels win

    @Test func explicitExpiryLabelWins() {
        // The labeled "保质期至" date must win over the bare production date even
        // though the production date appears first.
        let text = "生产日期 2026.01.01\n保质期至 2026.07.01"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 7, d: 1))
    }

    @Test func validityLabelWithColon() {
        #expect(components(ExpiryDateParser.parse("有效期至：2027-03-15")) == YMD(y: 2027, m: 3, d: 15))
    }

    @Test func englishBestBeforeLabel() {
        #expect(components(ExpiryDateParser.parse("BEST BEFORE 2026/12/31")) == YMD(y: 2026, m: 12, d: 31))
    }

    @Test func expLabel() {
        #expect(components(ExpiryDateParser.parse("EXP 2026.08.20")) == YMD(y: 2026, m: 8, d: 20))
    }

    @Test func expSubstringInWordDoesNotHijackLabeledExpiry() {
        // "exp" must match only as a standalone token — not inside EXPORT /
        // EXPERIENCE / EXPRESS — so a stray marketing date can't pre-empt the
        // correct 生产日期 + 保质期 derivation (tier 2).
        let text = "BEST EXPERIENCE 2030.01.01 生产2025.01.01 保质期1年"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 1, d: 1))
        // A bare "EXPORT <date>" must NOT be read as a labeled expiry.
        #expect(components(ExpiryDateParser.parse("EXPORT 2026.05.01\n生产2025.05.01 保质期3个月")) == YMD(y: 2025, m: 8, d: 1))
    }

    // MARK: Production date + duration derivation

    @Test func productionDatePlusDays() {
        // 生产日期 2026-01-01 + 保质期 90 天 = 2026-04-01.
        let text = "生产日期 2026-01-01\n保质期 90 天"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 4, d: 1))
    }

    @Test func productionDatePlusMonths() {
        // 生产日期 2026-01-15 + 保质期 6 个月 = 2026-07-15.
        let text = "生产日期：2026.01.15 保质期 6个月"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 7, d: 15))
    }

    @Test func productionDatePlusYears() {
        let text = "生产日期 2025年03月10日 保质期 2 年"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2027, m: 3, d: 10))
    }

    @Test func durationWithoutProductionMarkerUsesEarliestDate() {
        // No 生产 marker, but a bare date + a duration → earliest date + duration.
        let text = "2026.02.01 保质期 30 天"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 3, d: 3))
    }

    // MARK: Multiple candidates — latest plausible future date when unlabeled

    @Test func picksLatestWhenTwoBareDates() {
        // Two bare dates, no label, no duration: production-then-expiry ordering
        // means the later date is the expiry.
        let text = "2026.01.01\n2026.06.30"
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 6, d: 30))
    }

    // MARK: Noise guards — must NOT read prices / phones / batch codes as dates

    @Test func priceIsNotADate() {
        #expect(ExpiryDateParser.parse("¥12.50") == nil)
        #expect(ExpiryDateParser.parse("总计 45.30 元") == nil)
    }

    @Test func phoneNumberIsNotADate() {
        // A phone number's digit runs don't form a valid YYYYMMDD calendar day.
        #expect(ExpiryDateParser.parse("客服电话 400-820-9999") == nil)
    }

    @Test func invalidCalendarComponentsRejected() {
        // Month 13 / day 50 / Feb 30 are not real days → no date.
        #expect(ExpiryDateParser.parse("2026-13-01") == nil)
        #expect(ExpiryDateParser.parse("2026-05-50") == nil)
        #expect(ExpiryDateParser.parse("2026-02-30") == nil)
    }

    @Test func yearOutsideWindowRejected() {
        // A 4-digit run that isn't a sane year (batch code) must not parse.
        #expect(ExpiryDateParser.parse("1234-56-78") == nil)
        #expect(ExpiryDateParser.parse("批号 5012 0301") == nil)
    }

    @Test func emptyAndPlainTextReturnNil() {
        #expect(ExpiryDateParser.parse("") == nil)
        #expect(ExpiryDateParser.parse("配料表：水、糖、食用盐") == nil)
    }

    @Test func barNumberWithoutDateUnitIsNotMistakenForDuration() {
        // A bare quantity ("净含量 500 克") carries no shelf-life unit and no date,
        // so nothing should parse (the duration path requires both).
        #expect(ExpiryDateParser.parse("净含量 500 克") == nil)
    }

    // MARK: Realistic label end-to-end

    @Test func realisticPackagingLabel() {
        let text = """
        伊利 纯牛奶 250ml
        净含量 250 毫升
        生产日期 2026.05.01
        保质期 6个月
        """
        // 2026.05.01 + 6 months = 2026.11.01.
        #expect(components(ExpiryDateParser.parse(text)) == YMD(y: 2026, m: 11, d: 1))
    }
}
