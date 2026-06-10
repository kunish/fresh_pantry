import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for the PURE OCR-text post-processing (`ReceiptTextCleaner`) used by
/// the receipt-import flow. The Vision OCR itself is not tested (it needs the
/// engine + a real image); only the deterministic line cleaning / noise filtering
/// / joining is covered here, since that is the testable seam in front of the
/// existing AI text parse chain.
struct ReceiptTextCleanerTests {
    // MARK: clean — trims + drops blank lines, preserves order

    @Test func trimsAndDropsBlankLines() {
        let input = ["  牛奶 2 盒 ", "", "   ", "鸡蛋 一打"]
        #expect(ReceiptTextCleaner.clean(input) == ["牛奶 2 盒", "鸡蛋 一打"])
    }

    // MARK: clean — keeps real item lines (incl. mixed item + price)

    @Test func keepsItemLinesIncludingMixedPrice() {
        // A line that names an item AND carries a price is an item line, not noise.
        let input = ["西红柿 3 个 ¥9.90", "全麦面包 1 袋"]
        #expect(ReceiptTextCleaner.clean(input) == ["西红柿 3 个 ¥9.90", "全麦面包 1 袋"])
    }

    // MARK: clean — drops divider, price-only, and keyword noise rows

    @Test func dropsReceiptNoiseRows() {
        let input = [
            "永辉超市",          // store header keyword (超市? no) -> kept unless keyword
            "------------",      // divider
            "苹果 2 个",         // item, kept
            "12.50",             // price-only
            "¥ 9.90",            // price-only with currency
            "合计 ¥45.30",       // total keyword
            "微信支付 45.30",    // payment keyword
            "找零 0.00",         // change keyword
            "香蕉 1 把",         // item, kept
        ]
        #expect(ReceiptTextCleaner.clean(input) == ["永辉超市", "苹果 2 个", "香蕉 1 把"])
    }

    // MARK: isNoiseLine — divider lines (only punctuation / separators)

    @Test func dividerLinesAreNoise() {
        #expect(ReceiptTextCleaner.isNoiseLine("--------"))
        #expect(ReceiptTextCleaner.isNoiseLine("========"))
        #expect(ReceiptTextCleaner.isNoiseLine("******"))
        #expect(ReceiptTextCleaner.isNoiseLine("—————"))
    }

    // MARK: isNoiseLine — price-/quantity-only lines (no letters / CJK)

    @Test func priceOnlyLinesAreNoise() {
        #expect(ReceiptTextCleaner.isNoiseLine("12.50"))
        #expect(ReceiptTextCleaner.isNoiseLine("¥9.9"))
        #expect(ReceiptTextCleaner.isNoiseLine("$ 3.00"))
        #expect(ReceiptTextCleaner.isNoiseLine("2 x 1.50"))
        #expect(ReceiptTextCleaner.isNoiseLine("001234"))
    }

    // MARK: isNoiseLine — fullwidth-currency price line is still price-only

    @Test func fullwidthCurrencyPriceLineIsNoise() {
        // OCR may emit a fullwidth yen (￥, U+FFE5); the price line must still be
        // filtered (it carries no item name).
        #expect(ReceiptTextCleaner.isNoiseLine("\u{FFE5}9.90"))
    }

    // MARK: isNoiseLine — lines with item names are NOT price-only

    @Test func itemNameWithDigitsIsNotPriceOnly() {
        #expect(!ReceiptTextCleaner.isNoiseLine("牛奶 2 盒"))
        #expect(!ReceiptTextCleaner.isNoiseLine("Milk 1L"))
        #expect(!ReceiptTextCleaner.isNoiseLine("鸡蛋 12 个"))
    }

    // MARK: isNoiseLine — summary keyword rows (Chinese + English)

    @Test func summaryKeywordRowsAreNoise() {
        #expect(ReceiptTextCleaner.isNoiseLine("合计 45.30"))
        #expect(ReceiptTextCleaner.isNoiseLine("小计：40.00"))
        #expect(ReceiptTextCleaner.isNoiseLine("现金 50"))
        #expect(ReceiptTextCleaner.isNoiseLine("会员积分 120"))
        #expect(ReceiptTextCleaner.isNoiseLine("SUBTOTAL 12.00"))
        #expect(ReceiptTextCleaner.isNoiseLine("Total $45.30"))
        #expect(ReceiptTextCleaner.isNoiseLine("CASH 50.00"))
        #expect(ReceiptTextCleaner.isNoiseLine("Card Payment"))
        #expect(ReceiptTextCleaner.isNoiseLine("Thank you for shopping"))
    }

    // MARK: isNoiseLine — English item names that merely CONTAIN a keyword substring
    // must NOT be dropped (word-boundary match, not bare substring).
    @Test func englishItemNamesContainingKeywordSubstringAreKept() {
        #expect(!ReceiptTextCleaner.isNoiseLine("Cardamom"))      // contains "card"
        #expect(!ReceiptTextCleaner.isNoiseLine("Cashews"))       // contains "cash"
        #expect(!ReceiptTextCleaner.isNoiseLine("Chicken Tenders")) // contains "tender"
        #expect(!ReceiptTextCleaner.isNoiseLine("Total Greek Yogurt")) // brand "Total"… but a real item
        #expect(!ReceiptTextCleaner.isNoiseLine("Store Brand Milk"))   // contains "store"
    }

    // MARK: isNoiseLine — a plain item line is not noise

    @Test func plainItemLineIsNotNoise() {
        #expect(!ReceiptTextCleaner.isNoiseLine("有机西兰花"))
        #expect(!ReceiptTextCleaner.isNoiseLine("Whole Wheat Bread"))
    }

    // MARK: join — cleaned lines become a newline-joined text block

    @Test func joinsLinesWithNewlines() {
        #expect(ReceiptTextCleaner.join(["牛奶 2 盒", "鸡蛋 一打"]) == "牛奶 2 盒\n鸡蛋 一打")
    }

    // MARK: clean → join — end-to-end pure preprocessing of a small receipt

    @Test func cleanThenJoinProducesParserReadyText() {
        let raw = [
            "盒马鲜生",
            "================",
            "牛奶 2 盒",
            "8.50",
            "鸡蛋 1 打",
            "合计 ¥28.50",
            "微信支付",
            "谢谢惠顾",
        ]
        let text = ReceiptTextCleaner.join(ReceiptTextCleaner.clean(raw))
        #expect(text == "盒马鲜生\n牛奶 2 盒\n鸡蛋 1 打")
    }
}
