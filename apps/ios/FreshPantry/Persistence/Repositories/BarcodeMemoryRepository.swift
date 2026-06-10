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
    }
}
