import SwiftUI

/// Read-only recipe detail: a category-tinted hero (remote cover when present),
/// the name + meta row (category · difficulty · N 分钟), a favorite toggle, the
/// ingredient list (name + amount), numbered cooking steps, and a "做菜" CTA that
/// opens the cook-time deduction review (the only inventory-mutating affordance
/// here — built additively on top of the browse-only screen).
struct RecipeDetailView: View {
    let recipe: Recipe
    let store: RecipesStore
    /// CRUD owner for custom recipes — drives the edit form + delete. nil-safe:
    /// the edit/delete affordances only render when `isCustom` is true.
    var customStore: CustomRecipeStore?
    /// Whether this recipe is a user-authored custom one (vs a bundled corpus
    /// recipe). When true, the toolbar surfaces 编辑 + 删除.
    var isCustom: Bool = false

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    /// Built when "做菜" is tapped (inventory loaded → proposals via the factory),
    /// then presented as a review sheet. nil while idle. Wrapped because a bare
    /// array isn't `Identifiable` for `.sheet(item:)`.
    @State private var cookSession: CookSession?
    @State private var isPreparingCook = false
    @State private var showEditForm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                hero
                header
                if !recipe.description.trimmed.isEmpty {
                    Text(recipe.description)
                        .font(.fkBodyMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .padding(.horizontal, FkSpacing.lg)
                }
                ingredientsSection
                stepsSection
            }
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .safeAreaInset(edge: .bottom) { cookBar }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(recipe)
                } label: {
                    Image(systemName: store.isFavorite(recipe) ? "heart.fill" : "heart")
                }
                .tint(store.isFavorite(recipe) ? .fkDanger : .fkOnSurfaceVariant)
                .accessibilityLabel(store.isFavorite(recipe) ? "取消收藏" : "收藏")
            }
            if isCustom, customStore != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditForm = true
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("食谱操作")
                }
            }
        }
        .sheet(isPresented: $showEditForm) {
            if let customStore {
                CustomRecipeFormView(recipe: recipe, store: customStore)
            }
        }
        .confirmationDialog(
            "删除食谱",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    if let customStore, await customStore.remove(recipe.id) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除「\(recipe.name)」吗？此操作无法撤销。")
        }
        .sheet(item: $cookSession) { session in
            NavigationStack {
                DeductionReviewView(proposals: session.proposals) {
                    // Apply succeeded; the inventory/dashboard reload on their own
                    // `.task`/refresh, so nothing to do here beyond dismissing.
                }
            }
        }
        .task {
            // Snapshot affordance: `-initialRoute cook` opens the deduction review
            // directly (built from this recipe vs the live inventory) so the screen
            // can be screenshotted without a tap. Mirrors `-initialRoute add`.
            if RecipeDetailView.opensCookOnLaunch, cookSession == nil {
                await presentCook()
            }
        }
    }

    // MARK: 做菜 CTA + cook flow

    /// Bottom CTA that loads the live inventory, builds `[DeductionProposal]` via
    /// `DeductionProposalFactory.forRecipe`, and presents the deduction review.
    private var cookBar: some View {
        Button {
            Task { await presentCook() }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                if isPreparingCook {
                    ProgressView().tint(Color.fkOnPrimary)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(isPreparingCook ? "准备中…" : "做菜")
                    .font(.fkLabelLarge)
            }
            .foregroundStyle(Color.fkOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color.fkPrimary))
        }
        .buttonStyle(.fkPressable)
        .disabled(isPreparingCook || recipe.ingredients.isEmpty)
        .padding(.horizontal, FkSpacing.lg)
        .padding(.bottom, FkSpacing.sm)
        .accessibilityLabel("做菜并扣减库存")
    }

    /// Loads inventory, builds deduction proposals against it, and triggers the
    /// review sheet. A no-op if already preparing.
    private func presentCook() async {
        guard !isPreparingCook else { return }
        isPreparingCook = true
        defer { isPreparingCook = false }
        let inventory = (try? await dependencies.inventoryRepository.loadAllFor(dependencies.householdID)) ?? []
        cookSession = CookSession(proposals: DeductionProposalFactory.forRecipe(recipe, inventory))
    }

    /// Honors a `-initialRoute cook` launch argument (UI snapshots / tests).
    private static var opensCookOnLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return false
        }
        return args[index + 1] == "cook"
    }

    private var palette: FkCategoryColors { FkCategoryIcon.palette(for: recipe.category) }

    // MARK: Hero

    private var hero: some View {
        ZStack {
            palette.tint
            RecipeImage(source: recipe.imageUrl) { heroGlyph }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var heroGlyph: some View {
        Image(systemName: FkCategoryIcon.symbol(for: recipe.category))
            .font(.system(size: 72, weight: .semibold))
            .foregroundStyle(palette.ink)
    }

    // MARK: Header (name + meta)

    private var header: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            Text(recipe.name)
                .font(.fkHeadlineSmall)
                .foregroundStyle(Color.fkOnSurface)

            HStack(spacing: FkSpacing.md) {
                if !recipe.category.trimmed.isEmpty {
                    metaItem(systemImage: "tag", text: recipe.category)
                }
                metaItem(systemImage: "flame", text: recipe.difficultyLabel)
                metaItem(systemImage: "clock", text: "\(recipe.cookingMinutes) 分钟")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FkSpacing.lg)
    }

    private func metaItem(systemImage: String, text: String) -> some View {
        HStack(spacing: FkSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.fkLabelMedium)
        }
        .foregroundStyle(Color.fkOnSurfaceVariant)
    }

    // MARK: Ingredients

    @ViewBuilder
    private var ingredientsSection: some View {
        if !recipe.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                FkSectionHeader(title: "食材清单", count: recipe.ingredients.count)
                FkCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                            ingredientRow(ingredient)
                            if index < recipe.ingredients.count - 1 {
                                Rectangle().fill(Color.fkHair).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        HStack {
            Text(ingredient.name)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: FkSpacing.md)
            if !ingredient.amount.trimmed.isEmpty {
                Text(ingredient.amount)
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .padding(FkSpacing.lg)
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsSection: some View {
        if !recipe.steps.isEmpty {
            VStack(alignment: .leading, spacing: FkSpacing.sm) {
                FkSectionHeader(title: "烹饪步骤", count: recipe.steps.count)
                VStack(spacing: FkSpacing.sm) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(number: index + 1, text: step)
                    }
                }
            }
            .padding(.horizontal, FkSpacing.lg)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        FkCard {
            HStack(alignment: .top, spacing: FkSpacing.md) {
                Text("\(number)")
                    .font(.fkLabelMedium)
                    .foregroundStyle(Color.fkPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.fkPrimarySoft))
                Text(text)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// `Identifiable` wrapper around the built deduction proposals so the cook review
/// can drive `.sheet(item:)` (a bare `[DeductionProposal]` isn't `Identifiable`).
private struct CookSession: Identifiable {
    let id = UUID()
    let proposals: [DeductionProposal]
}
