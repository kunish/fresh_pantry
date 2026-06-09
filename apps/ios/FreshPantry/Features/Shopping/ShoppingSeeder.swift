import Foundation

#if DEBUG
/// DEBUG-only one-shot seeder so the Shopping screen is demonstrable on a fresh
/// install. Inserts ~6 varied sample items (across categories, a couple
/// pre-checked) only when the scope is empty and the run-once flag is unset.
/// Never compiled into release builds.
enum ShoppingSeeder {
    private static let didSeedKey = "fp.shopping.didSeedSamples.v1"

    /// Seeds samples if needed. Safe to call on every launch.
    static func seedIfNeeded(
        repository: ShoppingRepository,
        householdID: String,
        defaults: UserDefaults = .standard
    ) async {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        defaults.set(true, forKey: didSeedKey)

        let existing = (try? await repository.loadAllFor(householdID)) ?? []
        guard existing.isEmpty else { return }

        try? await repository.saveItems(householdID, sampleItems())
    }

    /// Specs: (name, detail, isChecked). Category comes from `FoodKnowledge` so
    /// the grouping/sorting is realistic and self-consistent.
    private static let specs: [(name: String, detail: String, isChecked: Bool)] = [
        ("牛奶", "2 盒", false),
        ("鸡蛋", "1 打", true),
        ("西红柿", "500 g", false),
        ("猪肉", "300 g", false),
        ("酱油", "1 瓶", true),
        ("苹果", "6 个", false),
    ]

    static func sampleItems() -> [ShoppingItem] {
        specs.enumerated().map { offset, spec in
            ShoppingItem(
                id: "seed_si_\(offset)_\(spec.name)",
                name: spec.name,
                detail: spec.detail,
                category: FoodKnowledge.categoryFor(spec.name),
                isChecked: spec.isChecked
            )
        }
    }
}
#endif
