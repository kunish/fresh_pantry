import Foundation
import SwiftData
import os

/// Device-local store for learned barcode → product mappings (see
/// `BarcodeMemoryRecord` for the no-sync scope decision). Mirrors the minimal
/// read/write shape of `FoodDetailsRepository`: `lookup` for the scan fast-path,
/// `upsert` for the learning write after a scanned item is saved.
///
/// FAILURE POLICY: this is a convenience cache, never a data path. Both methods
/// can throw (the caller logs + degrades to OFF / manual) — a barcode-memory
/// miss or write failure must never block scanning or saving.
@ModelActor
actor BarcodeMemoryRepository {
    /// Upper bound on stored rows. This is a device-local convenience cache, not
    /// a data path, so it must not grow without bound. Past this many rows, the
    /// least-recently-used mappings (oldest `lastUsedAt`) are evicted on the next
    /// learning write — `lastUsedAt` is the eviction key (its sole read side).
    static let maxEntries = 500

    /// Returns the learned mapping for a barcode, or `nil` when none / the
    /// barcode is blank. Bumps no recency on read (recency tracks SAVES, the
    /// signal of "still buying this", not lookups).
    func lookup(_ barcode: String) throws -> BarcodeMemory? {
        let key = barcode.trimmed
        guard !key.isEmpty else { return nil }
        let descriptor = FetchDescriptor<BarcodeMemoryRecord>(
            predicate: #Predicate { $0.barcode == key }
        )
        return try modelContext.fetch(descriptor).first?.value()
    }

    /// Learns / refreshes the mapping for a barcode (update existing row, else
    /// insert). Idempotent on the barcode key — re-saving the same product just
    /// updates name/category + recency, never duplicates. A blank barcode or a
    /// blank name is a no-op (nothing useful to learn).
    func upsert(barcode: String, name: String, category: String, now: Date = Date()) throws {
        let key = barcode.trimmed
        let trimmedName = name.trimmed
        guard !key.isEmpty, !trimmedName.isEmpty else { return }
        let canonicalCategory = FoodCategories.dropdownValue(category)

        let descriptor = FetchDescriptor<BarcodeMemoryRecord>(
            predicate: #Predicate { $0.barcode == key }
        )
        if let row = try modelContext.fetch(descriptor).first {
            row.name = trimmedName
            row.category = canonicalCategory
            row.lastUsedAt = now
        } else {
            modelContext.insert(
                BarcodeMemoryRecord(
                    barcode: key,
                    name: trimmedName,
                    category: canonicalCategory,
                    lastUsedAt: now
                )
            )
        }
        try modelContext.save()
        try enforceLimit(Self.maxEntries)
    }

    /// Bounds the store to `max` rows by deleting the least-recently-used ones
    /// (oldest `lastUsedAt` first). A no-op while at or under the cap, so the
    /// common upsert path only pays one `fetchCount`. This is the read side that
    /// makes `lastUsedAt` load-bearing: recency ranks rows for eviction.
    func enforceLimit(_ max: Int) throws {
        let total = try modelContext.fetchCount(FetchDescriptor<BarcodeMemoryRecord>())
        guard total > max else { return }
        var oldestFirst = FetchDescriptor<BarcodeMemoryRecord>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .forward)]
        )
        oldestFirst.fetchLimit = total - max
        for victim in try modelContext.fetch(oldestFirst) {
            modelContext.delete(victim)
        }
        try modelContext.save()
    }
}
