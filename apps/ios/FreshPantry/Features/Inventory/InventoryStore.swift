import Foundation

/// Feature store for the Inventory slice — the reusable `@Observable @MainActor`
/// template later features copy.
///
/// Owns the household's ingredients (kept in repo/insertion order — the
/// parity-critical source order is never mutated by display concerns) plus the
/// filter / search state, and exposes `displayItems`: a derived, urgency-sorted,
/// storage-filtered, name-searched projection. All domain mapping, scoping, and
/// sorting live here (or the repo); views never touch SwiftData directly.
@Observable
@MainActor
final class InventoryStore {
    /// Storage-area filter. `nil` = 全部 (all locations).
    enum StorageFilter: Equatable {
        case all
        case area(IconType)
    }

    private let repository: InventoryRepository
    /// Append-only food-departure log — the waste-stats source of truth. A manual
    /// removal-with-outcome appends one entry here (the ONLY non-cook log path).
    private let foodLogRepository: FoodLogRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps existing tests/previews local-only.
    private let syncWriter: SyncWriter?

    /// Repo/insertion-ordered items (the source of truth — never reordered here).
    private(set) var items: [Ingredient] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    var storageFilter: StorageFilter = .all
    var searchQuery: String = ""

    init(
        repository: InventoryRepository,
        foodLogRepository: FoodLogRepository,
        householdID: String,
        syncWriter: SyncWriter? = nil
    ) {
        self.repository = repository
        self.foodLogRepository = foodLogRepository
        self.householdID = householdID
        self.syncWriter = syncWriter
    }

    // MARK: Loading

    /// Loads the household scope off the repo actor and assigns on the main actor.
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            items = try await repository.loadAllFor(householdID)
        } catch {
            // Surface an empty scope rather than crashing; a load error simply
            // means "nothing to show" for this read-only slice.
            items = []
        }
    }

    // MARK: Mutations

    /// Deletes a row by stable identity (id first, else name-guarded positional
    /// match), persists the survivors, and updates local state. Returns whether
    /// a row was removed. The plain delete logs NO departure (kept intact for
    /// callers that don't want an outcome).
    @discardableResult
    func delete(_ target: Ingredient) async -> Bool {
        guard let index = indexOf(target) else { return false }
        let removed = items[index]
        var survivors = items
        survivors.remove(at: index)
        do {
            try await repository.saveItems(householdID, survivors)
            items = survivors
        } catch {
            return false
        }
        await enqueueDelete(removed)
        return true
    }

    /// Describes a completed removal-with-outcome so the caller can offer an undo
    /// that reverses BOTH sides (re-add the row + reverse the food-log append).
    struct RemovalUndo: Sendable {
        /// The removed row (re-inserted at its original index on undo).
        let ingredient: Ingredient
        let originalIndex: Int
        /// The logged departure's id, to point-delete on undo. Empty when nothing
        /// was logged (a defensive append no-op never happens here, but stays safe).
        let loggedEntryId: String
    }

    /// Removes a row AND appends a matching `FoodLogEntry` for the chosen outcome
    /// (吃完了 → `.consumed`, 扔掉了/过期 → `.wasted`). This is the manual-removal
    /// waste-stats input — the cook flow logs its own consumed departures, so a
    /// row is never double-logged. `wasExpiring` snapshots whether the batch was
    /// already past fresh. Returns a `RemovalUndo` (nil if no row matched) so the
    /// caller can reverse both sides.
    @discardableResult
    func remove(_ target: Ingredient, outcome: FoodLogOutcome, now: Date = Date()) async -> RemovalUndo? {
        guard let index = indexOf(target) else { return nil }
        let removed = items[index]
        var survivors = items
        survivors.remove(at: index)
        do {
            try await repository.saveItems(householdID, survivors)
            items = survivors
        } catch {
            return nil
        }

        // Log AFTER the inventory save lands (mirrors the cook flow's ordering).
        let entry = FoodLogEntry(
            id: FoodLogEntry.newId(),
            name: removed.name,
            category: FoodCategories.normalize(removed.category) ?? FoodCategories.other,
            outcome: outcome,
            loggedAt: now,
            wasExpiring: removed.state != .fresh
        )
        try? await foodLogRepository.append(householdID, entry)
        await enqueueDelete(removed)
        return RemovalUndo(ingredient: removed, originalIndex: index, loggedEntryId: entry.id)
    }

    /// Reverses a removal-with-outcome: re-inserts the row at its original index
    /// and point-deletes the logged departure via `FoodLogRepository.deleteEntry`
    /// (NEVER `saveEntries`, which would drop window-outside history). Returns
    /// whether the row was re-added.
    @discardableResult
    func undoRemove(_ undo: RemovalUndo) async -> Bool {
        var restored = items
        let index = min(max(undo.originalIndex, 0), restored.count)
        restored.insert(undo.ingredient, at: index)
        do {
            try await repository.saveItems(householdID, restored)
            items = restored
        } catch {
            return false
        }
        if !undo.loggedEntryId.isEmpty {
            try? await foodLogRepository.deleteEntry(householdID, undo.loggedEntryId)
        }
        // Undelete path: re-assert the restored row remotely via a full-row write
        // (`.update`), which clears the soft-delete the original `.delete` set.
        if let patch = DomainJSON.valueMap(undo.ingredient) {
            await syncWriter?.enqueue(
                entityType: .inventoryItem,
                entityId: undo.ingredient.id,
                operation: .update,
                patch: patch,
                baseVersion: undo.ingredient.remoteVersion
            )
        }
        return true
    }

    /// Enqueues a soft-delete outbox op for `removed` (the gateway derives
    /// `deleted_at`). Skipped — still a successful local delete — when the row
    /// can't be serialized to a wire patch.
    private func enqueueDelete(_ removed: Ingredient) async {
        guard let patch = DomainJSON.valueMap(removed) else { return }
        await syncWriter?.enqueue(
            entityType: .inventoryItem,
            entityId: removed.id,
            operation: .delete,
            patch: patch,
            baseVersion: removed.remoteVersion
        )
    }

    // MARK: Derived view data

    /// The list the view renders: storage filter → name search → urgency sort.
    var displayItems: [Ingredient] {
        let filtered = items
            .filter(matchesStorageFilter)
            .filter(matchesSearch)
        return sortByUrgency(filtered)
    }

    /// True when there are stored items but the active filter/search hides them
    /// (drives the "no results" vs "empty pantry" copy).
    var hasActiveQuery: Bool {
        !searchQuery.trimmed.isEmpty || storageFilter != .all
    }

    /// Count of items in each storage area, for the filter-chip badges.
    func count(for filter: StorageFilter) -> Int {
        switch filter {
        case .all: return items.count
        case let .area(area): return items.filter { $0.storage == area }.count
        }
    }

    // MARK: Filtering / sorting internals

    private func matchesStorageFilter(_ item: Ingredient) -> Bool {
        switch storageFilter {
        case .all: return true
        case let .area(area): return item.storage == area
        }
    }

    private func matchesSearch(_ item: Ingredient) -> Bool {
        let query = searchQuery.trimmed.lowercased()
        if query.isEmpty { return true }
        return item.name.lowercased().contains(query)
    }

    /// Sort: most-severe state first (expired→urgent→expiringSoon→fresh), then
    /// soonest expiry first (nil expiry last), stable by original index.
    private func sortByUrgency(_ list: [Ingredient]) -> [Ingredient] {
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon, .fresh]
        func rank(_ state: FreshnessState) -> Int { order.firstIndex(of: state) ?? order.count }

        return list.enumerated().sorted { lhs, rhs in
            let lRank = rank(lhs.element.state)
            let rRank = rank(rhs.element.state)
            if lRank != rRank { return lRank < rRank }

            switch (lhs.element.expiryDate, rhs.element.expiryDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.offset < rhs.offset // stable by source order
            }
        }.map(\.element)
    }

    /// Stable identity resolution: id first (when non-empty), else the first
    /// name-matching positional row (mirrors `inventoryIndexOf`).
    private func indexOf(_ target: Ingredient) -> Int? {
        if !target.id.isEmpty, let byId = items.firstIndex(where: { $0.id == target.id }) {
            return byId
        }
        return items.firstIndex(where: { $0 == target })
            ?? items.firstIndex(where: { $0.name == target.name })
    }
}
