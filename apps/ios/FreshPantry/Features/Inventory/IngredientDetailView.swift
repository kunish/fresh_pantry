import SwiftUI

/// Read-only ingredient detail with a category-tinted hero, a quantity /
/// freshness split card, a storage / category / shelf-life info list, and a
/// destructive delete (confirmed) that calls the store and pops.
struct IngredientDetailView: View {
    let ingredient: Ingredient
    let store: InventoryStore

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showOutcomePrompt = false
    @State private var isDeleting = false
    /// Cache-first OFF food-details lookup driving the nutrition card. Built lazily
    /// from `dependencies` on first appearance (mirrors the Flutter auto-fetch).
    @State private var detailsStore: FoodDetailsStore?
    /// Holds the just-removed row so the undo banner can reverse BOTH the
    /// inventory removal and the food-log append before the screen pops.
    @State private var pendingUndo: InventoryStore.RemovalUndo?

    private var palette: FkCategoryColors { FkCategoryIcon.palette(for: ingredient.category) }

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.lg) {
                hero
                quantityAndFreshnessCard
                foodDetailsSection
                infoList
            }
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .navigationTitle(ingredient.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if detailsStore == nil {
                let store = FoodDetailsStore(
                    ingredient: ingredient,
                    repository: dependencies.foodDetailsRepository,
                    client: dependencies.foodDetailsClient
                )
                detailsStore = store
                await store.load()
            }
        }
        .overlay(alignment: .bottom) { undoBanner }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showOutcomePrompt = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.fkDanger)
                .disabled(isDeleting)
            }
        }
        .confirmationDialog(
            "「\(ingredient.name)」要移除",
            isPresented: $showOutcomePrompt,
            titleVisibility: .visible
        ) {
            Button("吃完 / 用掉了") { Task { await performRemove(outcome: .consumed) } }
            Button("没吃完,扔了") { Task { await performRemove(outcome: .wasted) } }
            Button("仅移除") { Task { await performDelete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("它怎么了?用于统计你的减废成效。")
        }
    }

    // MARK: Undo banner

    /// A transient banner shown after a removal-with-outcome. Tapping 撤销 reverses
    /// the inventory removal AND point-deletes the logged departure; otherwise it
    /// auto-dismisses the screen after a short grace period.
    @ViewBuilder
    private var undoBanner: some View {
        if let undo = pendingUndo {
            HStack(spacing: FkSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.fkSuccess)
                Text("已记录「\(undo.ingredient.name)」")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Spacer(minLength: FkSpacing.sm)
                Button("撤销") { Task { await performUndo(undo) } }
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkPrimary)
            }
            .padding(.horizontal, FkSpacing.lg)
            .padding(.vertical, FkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerLowest)
            )
            .fkCardShadow()
            .padding(.horizontal, FkSpacing.lg)
            .padding(.bottom, FkSpacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.loggedEntryId) {
                // Grace period for undo, then pop. Cancelled if the row is undone
                // (pendingUndo clears → this task is torn down before the sleep ends).
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { dismiss() }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: FkSpacing.md) {
            FkCategoryAvatar(
                imageUrl: ingredient.imageUrl,
                category: ingredient.category,
                size: 92,
                cornerRadius: FkRadius.xxl,
                iconScale: 0.55
            )

            VStack(spacing: FkSpacing.xs) {
                HStack(spacing: FkSpacing.sm) {
                    Text(ingredient.name)
                        .font(.fkHeadlineSmall)
                        .foregroundStyle(Color.fkOnSurface)
                    if ingredient.state != .fresh {
                        UrgencyBadge(state: ingredient.state)
                    }
                }
                Text("\(FoodCategories.dropdownValue(ingredient.category)) · \(ingredient.storage.storageAreaLabel)")
                    .font(.fkLabelMedium)
                    .foregroundStyle(palette.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FkSpacing.huge)
        .background(palette.tint)
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: FkRadius.hero,
                bottomTrailingRadius: FkRadius.hero,
                style: .continuous
            )
        )
    }

    // MARK: Quantity + freshness

    private var quantityAndFreshnessCard: some View {
        let freshnessColor = ingredient.state == .expired ? Color.fkDanger : ingredient.state.statusStyle.foreground
        return FkCard {
            HStack(alignment: .top, spacing: 0) {
                statColumn(
                    label: "当前数量",
                    value: ingredient.quantity,
                    unit: ingredient.unit,
                    valueColor: .fkOnSurface
                )
                Rectangle()
                    .fill(Color.fkHair)
                    .frame(width: 0.5)
                statColumn(
                    label: "新鲜度",
                    value: "\(Int((min(max(ingredient.freshnessPercent, 0), 1) * 100).rounded()))",
                    unit: "%",
                    hint: ingredient.expiryLabel,
                    valueColor: freshnessColor
                )
            }
        }
        .padding(.horizontal, FkSpacing.lg)
    }

    private func statColumn(
        label: String,
        value: String,
        unit: String,
        hint: String? = nil,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: FkSpacing.xs) {
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: FkSpacing.xs) {
                Text(value)
                    .font(.fkHeroSubStat)
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FkSpacing.md)
    }

    // MARK: Food details (OFF) — image / description / nutrition

    /// The OFF-enriched section: a product image + description card and a per-100g
    /// nutrition card, each rendered only when the loaded details supply them.
    /// Renders nothing in idle / loading / not-found / error (the screen already
    /// shows the local quantity + info, so a failed lookup is silent).
    @ViewBuilder
    private var foodDetailsSection: some View {
        if case let .loaded(details) = detailsStore?.state {
            if hasProductCard(details) {
                productCard(details)
                    .padding(.horizontal, FkSpacing.lg)
            }
            if let nutrition = details.nutrition, nutrition.hasAny {
                NutritionCard(nutrition: nutrition)
                    .padding(.horizontal, FkSpacing.lg)
            }
        }
    }

    /// The product card is worth showing only when OFF added something beyond the
    /// local data — a real image and/or a non-placeholder description.
    private func hasProductCard(_ details: FoodDetails) -> Bool {
        let hasImage = !(details.imageUrl ?? "").trimmed.isEmpty
        let hasDescription = !details.description.trimmed.isEmpty
            && !isPlaceholderFoodDescription(details.description)
        return hasImage || hasDescription
    }

    private func productCard(_ details: FoodDetails) -> some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                if let imageUrl = details.imageUrl, !imageUrl.trimmed.isEmpty {
                    FkCategoryAvatar(
                        imageUrl: imageUrl,
                        category: details.category,
                        size: 72,
                        cornerRadius: FkRadius.lg,
                        iconScale: 0.5
                    )
                }
                if !details.description.trimmed.isEmpty,
                   !isPlaceholderFoodDescription(details.description) {
                    Text(details.description)
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("数据来源：Open Food Facts")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }

    // MARK: Info list

    private var infoList: some View {
        FkCard(padding: 0) {
            VStack(spacing: 0) {
                infoRow("分类", FoodCategories.dropdownValue(ingredient.category))
                divider
                infoRow("存放位置", ingredient.storage.storageAreaLabel)
                if let shelfLife = ingredient.shelfLifeDays, shelfLife > 0 {
                    divider
                    infoRow("保质期建议", "\(shelfLife)天")
                }
                if let expiry = ingredient.expiryDate {
                    divider
                    infoRow("到期日", Self.dateFormatter.string(from: expiry))
                }
            }
        }
        .padding(.horizontal, FkSpacing.lg)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            Spacer()
            Text(value)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
        }
        .padding(FkSpacing.lg)
    }

    private var divider: some View {
        Rectangle().fill(Color.fkHair).frame(height: 0.5)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: Delete / remove-with-outcome

    /// Removes the row and logs the chosen outcome (consumed/wasted), then shows
    /// the undo banner (which pops after its grace period). The undo handle is the
    /// only path that can reverse the food-log append.
    private func performRemove(outcome: FoodLogOutcome) async {
        isDeleting = true
        let undo = await store.remove(ingredient, outcome: outcome)
        isDeleting = false
        if let undo {
            withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = undo }
        } else {
            dismiss() // nothing matched (already gone) — just leave the screen
        }
    }

    /// Plain remove with NO departure logged (the "仅移除" choice).
    private func performDelete() async {
        isDeleting = true
        let removed = await store.delete(ingredient)
        isDeleting = false
        if removed { dismiss() }
    }

    /// Reverses a removal-with-outcome (re-add row + point-delete the logged
    /// entry) and clears the banner, keeping the user on the detail screen.
    private func performUndo(_ undo: InventoryStore.RemovalUndo) async {
        _ = await store.undoRemove(undo)
        withAnimation(FkMotion.animation(FkMotion.standard, reduceMotion: reduceMotion)) { pendingUndo = nil }
    }
}
