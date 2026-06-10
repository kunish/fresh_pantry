import Foundation
import SwiftData

/// A device-local "barcode → product" learning row. The FIRST time a scanned
/// barcode is saved to inventory we remember its name + category here, so the
/// SECOND scan of the same product fills the form instantly — offline, with no
/// OFF round-trip. The differentiator vs `FoodDetailsCacheRecord`: that store
/// caches OFF *nutrition by name/barcode*; THIS store learns the user's own
/// *naming + category* for a barcode (e.g. a local/生鲜 product OFF never knew).
///
/// SCOPE — DELIBERATELY NOT SYNCED (no outbox / Supabase): this is per-device
/// convenience learning, not household-shared data. The mapping is shaped by
/// what one person scanned + how they named it on THIS phone; pushing it to the
/// shared household would leak one member's ad-hoc naming onto everyone and
/// invent a second source of truth for product identity. If two members each
/// scan the same product, each device simply learns it once. Keep this row out
/// of `RemoteRowCodec` / the sync schema.
@Model
final class BarcodeMemoryRecord {
    /// EAN/UPC payload — the natural unique key (already trimmed by the caller).
    @Attribute(.unique) var barcode: String = ""
    /// The name the user kept for this barcode on the most recent save.
    var name: String = ""
    /// Canonical app category (one of `FoodCategories.values`).
    var category: String = ""
    /// Last save that touched this row — lets a future "recently learned" view
    /// or eviction sort by recency without a separate access log.
    var lastUsedAt: Date = Date.distantPast

    init(barcode: String, name: String, category: String, lastUsedAt: Date) {
        self.barcode = barcode
        self.name = name
        self.category = category
        self.lastUsedAt = lastUsedAt
    }

    func value() -> BarcodeMemory {
        BarcodeMemory(barcode: barcode, name: name, category: category, lastUsedAt: lastUsedAt)
    }
}

/// Sendable snapshot of a learned barcode mapping, returned across the
/// `BarcodeMemoryRepository` actor boundary (the `@Model` row itself stays
/// inside the actor's `ModelContext`).
struct BarcodeMemory: Equatable, Sendable {
    let barcode: String
    let name: String
    let category: String
    let lastUsedAt: Date
}
