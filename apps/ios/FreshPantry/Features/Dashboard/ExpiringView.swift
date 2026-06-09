import SwiftUI

/// The 临期 screen, pushed from the Dashboard: the household's non-fresh
/// inventory (state ∈ {expiringSoon, urgent, expired}), urgency-sorted and
/// sectioned by tier (已过期 → 快过期 → 即将过期).
///
/// Builds its own `ExpiringStore` from the injected `AppDependencies` (the
/// reusable feature pattern) so it reloads independently of the home tab.
/// Read-only: rows render as `IngredientRow`s. SwiftData is never touched here.
struct ExpiringView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: ExpiringStore?

    var body: some View {
        Group {
            if let store {
                ExpiringContent(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle("临期提醒")
        .navigationBarTitleDisplayMode(.inline)
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the expiring list re-scopes to the new household
        // rather than keeping the prior scope's stale rows.
        .task(id: dependencies.householdID) {
            let store = ExpiringStore(
                repository: dependencies.inventoryRepository,
                householdID: dependencies.householdID
            )
            self.store = store
            await store.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the expiring list reflects inventory pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }
}

/// Inner content bound to a live store.
private struct ExpiringContent: View {
    let store: ExpiringStore

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.tiers.isEmpty {
                FkEmptyState(
                    systemImage: "checkmark.circle",
                    title: "暂无临期食材",
                    message: "冰箱状态健康，继续保持！"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tierList
            }
        }
        .background(Color.fkSurface)
        .refreshable { await store.load() }
    }

    private var tierList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.xl) {
                ForEach(Array(store.tiers.enumerated()), id: \.element.id) { sectionIndex, tier in
                    VStack(alignment: .leading, spacing: FkSpacing.sm) {
                        tierHeader(tier)
                            .padding(.horizontal, FkSpacing.lg)

                        LazyVStack(spacing: FkSpacing.sm) {
                            ForEach(Array(tier.items.enumerated()), id: \.element.fkListIdentityKey) { index, item in
                                FkCard {
                                    IngredientRow(ingredient: item)
                                }
                                .fkEntrance(index: sectionIndex + index)
                            }
                        }
                        .padding(.horizontal, FkSpacing.lg)
                    }
                }
            }
            .padding(.top, FkSpacing.md)
            .padding(.bottom, FkSpacing.huge)
        }
    }

    private func tierHeader(_ tier: ExpiringStore.Tier) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Circle()
                .fill(tier.state.statusStyle.foreground)
                .frame(width: 8, height: 8)
            Text(tier.state.expiringSectionTitle)
                .font(.fkTitleMedium)
                .foregroundStyle(Color.fkOnSurface)
            Text("\(tier.items.count) 件")
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
    }
}

extension Ingredient {
    /// Stable list identity for `ForEach` shared by the Dashboard preview and the
    /// Expiring tiers (id when persisted, else a name+storage composite for
    /// local-only rows). Named distinctly from the Inventory view's fileprivate
    /// `identityKey` to avoid a same-type redeclaration.
    var fkListIdentityKey: String {
        id.isEmpty ? "\(name)\u{0}\(storage.rawValue)\u{0}\(quantity)\u{0}\(unit)" : id
    }
}
