import Foundation

/// Helpers for the per-household `updated_at` inbound-sync watermark.
enum SyncCursor {
    /// The latest `updated_at` across raw Supabase rows (pre-decode).
    static func maxUpdatedAt(in rows: [[String: JSONValue]]) -> Date? {
        rows.compactMap { row -> Date? in
            guard case let .string(raw) = row["updated_at"] else { return nil }
            return JSONDate.parse(raw)
        }.max()
    }

    /// Advances `cursor` to the max `updated_at` seen in `rows`, if any.
    static func advance(_ cursor: Date?, with rows: [[String: JSONValue]]) -> Date? {
        guard let latest = maxUpdatedAt(in: rows) else { return cursor }
        guard let cursor else { return latest }
        return max(cursor, latest)
    }
}
