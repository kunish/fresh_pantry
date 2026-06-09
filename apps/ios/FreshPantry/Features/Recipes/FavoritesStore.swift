import Foundation

/// UserDefaults-backed favorite-recipe ids — the reusable KV-settings-store
/// pattern later settings features (dietary exclusions, reminders, ai-settings)
/// copy.
///
/// Persists a `Set<String>` of recipe ids as a JSON **string array** under
/// `favorite_recipe_ids`, byte-compatible with the Flutter `FavoriteRecipesRepo`
/// so a future Supabase/household sync can read either side's blob. Decode is
/// defensive: a missing key, non-array JSON, or a malformed value all fall back
/// to an empty set (mirrors the Flutter repo's `catch -> {}`).
///
/// `@Observable @MainActor` so SwiftUI views observe `favoriteIDs` mutations and
/// the persisted write stays on the main actor. The `UserDefaults` suite is
/// injectable so tests run against an isolated suite (no shared global state).
@Observable
@MainActor
final class FavoritesStore {
    /// Storage key — matches Flutter `favorite_recipes_repo` for sync parity.
    static let storageKey = "favorite_recipe_ids"

    private let defaults: UserDefaults

    /// The live favorite-id set. Mutations persist synchronously to `defaults`.
    private(set) var favoriteIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.favoriteIDs = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: Queries

    func isFavorite(_ id: String) -> Bool {
        favoriteIDs.contains(id)
    }

    // MARK: Mutations

    /// Toggles a recipe id (ignores blank ids — they can't be addressed) and
    /// persists the new set. Returns the resulting favorite state.
    @discardableResult
    func toggle(_ id: String) -> Bool {
        let trimmed = id.trimmed
        guard !trimmed.isEmpty else { return false }
        let nowFavorite: Bool
        if favoriteIDs.contains(trimmed) {
            favoriteIDs.remove(trimmed)
            nowFavorite = false
        } else {
            favoriteIDs.insert(trimmed)
            nowFavorite = true
        }
        persist()
        return nowFavorite
    }

    // MARK: Persistence (the reusable JSON-string-array KV codec)

    /// Encodes the id set as a sorted JSON string array and writes the blob.
    /// Sorting keeps the persisted payload stable/diff-friendly across launches.
    private func persist() {
        let array = favoriteIDs.sorted()
        guard
            let data = try? JSONSerialization.data(withJSONObject: array),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// Defensive decode: nil/empty/non-array/malformed → empty set; otherwise the
    /// non-blank string elements (mirrors the Flutter repo's lenient load).
    static func decode(_ raw: String?) -> Set<String> {
        guard
            let raw, !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return []
        }
        let ids = array.compactMap { $0 as? String }.filter { !$0.isEmpty }
        return Set(ids)
    }
}
