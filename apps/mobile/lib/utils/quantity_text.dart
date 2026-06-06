// lib/utils/quantity_text.dart
//
// Single source of truth for two quantity-string rules that were previously
// copy-pasted across the intake / deduction / recipe flows:
//
//  * [parseLeadingQuantity] splits a free-text amount ("3 个", "1.5kg") into its
//    leading numeric magnitude and the remaining unit text. Callers keep their
//    own trimming / defaulting / fallback-unit policy; this helper owns only the
//    regex + group extraction so the intake and deduction flows can never drift
//    on how a quantity string is interpreted.
//  * [formatQuantity] renders a double as an int string when whole, else as a
//    decimal string rounded to 2 places — so binary float artifacts like
//    "1.2000000000000002" can never leak into a stored / displayed quantity.

/// Matches a leading decimal magnitude followed by optional unit text.
///
/// Decimal-only on purpose: the richer fraction/range dialect ("1/2", "1-2")
/// is owned separately by `recipe_draft_apply.dart` and is intentionally not
/// folded in here, since it carries different group semantics.
final _leadingQuantityRe = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$');

/// Splits a (pre-trimmed) amount string into its leading numeric magnitude and
/// the remaining text. Returns null when there is no leading number.
///
/// The returned `remainder` is trimmed; `magnitude` is the raw numeric token.
({String magnitude, String remainder})? parseLeadingQuantity(String input) {
  final match = _leadingQuantityRe.firstMatch(input);
  if (match == null) return null;
  return (
    magnitude: match.group(1) ?? '',
    remainder: (match.group(2) ?? '').trim(),
  );
}

/// Renders [n] without trailing-zero / float-artifact noise: a whole number
/// becomes an int string, otherwise a 2-decimal-rounded decimal string.
String formatQuantity(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return double.parse(n.toStringAsFixed(2)).toString();
}
