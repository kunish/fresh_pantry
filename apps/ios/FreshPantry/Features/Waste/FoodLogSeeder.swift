import Foundation

#if DEBUG
/// DEBUG-only one-shot seeder so the 减废统计 screen is demonstrable on a fresh
/// install. Appends ~12 food-departure entries spread across the last ~30 days —
/// a mix of consumed + wasted across the canonical categories, some flagged
/// `wasExpiring` (so 抢救临期 is non-zero). Only seeds when the scope is empty and
/// the run-once flag is unset. Never compiled into release builds.
enum FoodLogSeeder {
    private static let didSeedKey = "fp.foodLog.didSeedSamples.v1"

    /// Specs: (name, category, outcome, daysAgo, wasExpiring). Tuned so the
    /// headline use-up rate is a realistic ~75% with a visible 抢救临期 count and a
    /// category breakdown that has both consumed + wasted rows.
    private static let specs: [(name: String, category: String, outcome: FoodLogOutcome, daysAgo: Int, wasExpiring: Bool)] = [
        ("牛奶", FoodCategories.dairyAndEggs, .consumed, 1, true),
        ("鸡蛋", FoodCategories.dairyAndEggs, .consumed, 2, false),
        ("菠菜", FoodCategories.freshProduce, .wasted, 3, true),
        ("苹果", FoodCategories.freshProduce, .consumed, 4, false),
        ("西兰花", FoodCategories.freshProduce, .consumed, 6, true),
        ("鸡胸肉", FoodCategories.meatAndSeafood, .consumed, 8, true),
        ("三文鱼", FoodCategories.meatAndSeafood, .wasted, 11, true),
        ("酸奶", FoodCategories.dairyAndEggs, .consumed, 13, false),
        ("香菜", FoodCategories.herbsAndSpices, .wasted, 16, true),
        ("番茄", FoodCategories.freshProduce, .consumed, 19, false),
        ("豆腐", FoodCategories.other, .consumed, 23, false),
        ("生菜", FoodCategories.freshProduce, .wasted, 27, true),
    ]

    /// Seeds samples if needed. Safe to call on every launch. `now` is injectable
    /// for determinism in non-production callers.
    static func seedIfNeeded(
        repository: FoodLogRepository,
        householdID: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) async {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        defaults.set(true, forKey: didSeedKey)

        let existing = (try? await repository.loadAllFor(householdID)) ?? []
        guard existing.isEmpty else { return }

        for entry in sampleEntries(now: now) {
            try? await repository.append(householdID, entry)
        }
    }

    /// Builds the deterministic sample entries from `specs`, offsetting each by its
    /// `daysAgo` from `now`. Stable seed ids so re-runs upsert in place.
    static func sampleEntries(now: Date = Date()) -> [FoodLogEntry] {
        let calendar = Calendar.current
        return specs.enumerated().map { offset, spec in
            let loggedAt = calendar.date(byAdding: .day, value: -spec.daysAgo, to: now) ?? now
            return FoodLogEntry(
                id: "seed_fl_\(offset)_\(spec.name)",
                name: spec.name,
                category: spec.category,
                outcome: spec.outcome,
                loggedAt: loggedAt,
                wasExpiring: spec.wasExpiring
            )
        }
    }
}
#endif
