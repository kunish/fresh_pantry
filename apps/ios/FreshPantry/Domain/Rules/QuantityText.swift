import Foundation

/// Single source of truth for two quantity-string rules ported verbatim from
/// `lib/utils/quantity_text.dart`.
///
///  * `parseLeadingQuantity` splits a free-text amount ("3 个", "1.5kg") into its
///    leading numeric magnitude and the remaining unit text.
///  * `formatQuantity` renders a double as an int string when whole, else as a
///    decimal string rounded to <=2 places — so binary float artifacts like
///    "1.2000000000000002" can never leak into a stored / displayed quantity.
enum QuantityText {
    /// Matches a leading decimal magnitude followed by optional unit text.
    /// `^(\d+(?:\.\d+)?)\s*(.*)$` — decimal-only on purpose (fraction/range
    /// dialect lives elsewhere).
    private static let leadingQuantityRe = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)\s*(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    /// Splits a (pre-trimmed) amount string into its leading numeric magnitude
    /// and the remaining (trimmed) text. Returns nil when there is no leading
    /// number. `magnitude` is the raw numeric token.
    static func parseLeadingQuantity(_ input: String) -> (magnitude: String, remainder: String)? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = leadingQuantityRe.firstMatch(in: input, options: [], range: range) else {
            return nil
        }
        let magnitude = group(match, 1, in: input) ?? ""
        let remainder = (group(match, 2, in: input) ?? "").trimmed
        return (magnitude, remainder)
    }

    /// Renders `n` without trailing-zero / float-artifact noise: a whole number
    /// becomes an int string, otherwise a 2-decimal-rounded decimal string.
    static func formatQuantity(_ n: Double) -> String {
        if n == n.rounded() {
            return String(Int(n))
        }
        // Mirror Dart `double.parse(n.toStringAsFixed(2)).toString()`: round to
        // 2 decimals, then drop trailing zeros (e.g. 1.20 -> "1.2", 1.00 -> "1").
        let rounded = (n * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in string: String) -> String? {
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: string) else {
            return nil
        }
        return String(string[range])
    }
}
