import Foundation

/// Pure decision for what a scanned barcode prefills, by priority:
///
///   1. LOCAL memory hit  → fill name/category from what the user saved last
///      time on this device ("上次录入" provenance). Offline, zero OFF round-trip.
///   2. OFF hit           → fill from the Open Food Facts lookup (unchanged
///      legacy behavior when there's no local memory).
///   3. NO hit            → DON'T dead-end the user at the scan: drop straight
///      into the manual form with just the barcode prefilled + a gentle notice.
///
/// Kept as a pure function (no SwiftUI / SwiftData / network) so the priority,
/// the empty-result handling, and the invalid-barcode guard are unit-testable.
/// The view performs the actual I/O (memory lookup, then OFF) and feeds the
/// results here; it then applies the resulting prefill to the form.
enum BarcodeScanResolution {
    /// The chosen prefill outcome for a scan.
    enum Decision: Equatable {
        /// Use the device-local learned mapping (name + canonical category).
        case localMemory(name: String, category: String)
        /// Use the Open Food Facts details.
        case openFoodFacts(FoodDetails)
        /// Neither source resolved — prefill the barcode only and let the user
        /// fill the rest by hand (no longer a dead end).
        case manualFallback
        /// The scanned payload was blank / unusable — nothing to do.
        case invalid
    }

    /// Resolve the prefill decision. `localMemory` wins when present (it reflects
    /// THIS user's own naming + a prior real save); else fall back to the OFF
    /// `details`; else manual. A blank barcode short-circuits to `.invalid` so
    /// the caller can ignore the scan rather than open an empty form.
    static func decide(
        barcode: String,
        localMemory: BarcodeMemory?,
        offDetails: FoodDetails?
    ) -> Decision {
        guard !barcode.trimmed.isEmpty else { return .invalid }

        if let localMemory, !localMemory.name.trimmed.isEmpty {
            return .localMemory(
                name: localMemory.name,
                category: FoodCategories.dropdownValue(localMemory.category)
            )
        }
        if let offDetails {
            return .openFoodFacts(offDetails)
        }
        return .manualFallback
    }
}
