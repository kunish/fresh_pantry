import SwiftUI

/// The 首页 tab: a data-backed home hub summarizing the household's pantry —
/// a tinted hero with headline + sub-stats, a 临期提醒 preview that pushes the
/// full `ExpiringView`, and a 购物清单 summary that switches to the 购物 tab.
///
/// Builds its `DashboardStore` from the injected `AppDependencies` (the reusable
/// feature pattern). In DEBUG it runs the inventory + shopping seeders (the same
/// idempotent one-shots the other tabs use) before loading, so 首页 has data even
/// when opened first. SwiftData is never touched here.
struct DashboardView: View {
    /// Switches the root tab selection — used by the 购物清单 summary row to jump
    /// to the 购物 tab. Injected by `RootView`.
    var onSelectShopping: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @State private var store: DashboardStore?
    /// Programmatic stack path. Normally empty; the `-initialRoute` launch hook
    /// pre-seeds it (in `.task`) so a pushed screen (e.g. 膳食计划) can be
    /// snapshotted directly without a tap.
    @State private var path: [DashboardRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let store {
                    DashboardContent(store: store, onSelectShopping: onSelectShopping)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("首页")
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .expiring: ExpiringView()
                case .mealPlan: MealPlanView()
                case .wasteInsights: WasteInsightsView()
                case .lowStock: LowStockView(onSelectShopping: onSelectShopping)
                }
            }
        }
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the home hub re-scopes to the new household rather
        // than summarizing the prior scope's stale rows.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            // Apply the `-initialRoute` snapshot hook once, before first load.
            let initial = DashboardView.initialPath()
            if !initial.isEmpty { path = initial }
            #if DEBUG
            // Sample data is for the local-only personal scope only — a real
            // household's rows come from sync, never the seeder.
            if householdID.isEmpty {
                await InventorySeeder.seedIfNeeded(
                    repository: dependencies.inventoryRepository,
                    householdID: householdID
                )
                await ShoppingSeeder.seedIfNeeded(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID
                )
            }
            #endif
            let store = DashboardStore(
                inventoryRepository: dependencies.inventoryRepository,
                shoppingRepository: dependencies.shoppingRepository,
                householdID: householdID
            )
            self.store = store
            await store.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the dashboard reflects inventory/shopping pulled from other members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }
}

/// Navigation routes pushed from the Dashboard.
enum DashboardRoute: Hashable {
    case expiring
    case mealPlan
    case wasteInsights
    case lowStock
}

extension DashboardView {
    /// Honors a `-initialRoute <name>` launch argument by pre-seeding the
    /// navigation path, so a Dashboard-pushed screen can be snapshotted directly
    /// without a tap (a UI-snapshot affordance like `-initialTab`). Supports
    /// `mealplan` and `waste`; anything else starts at the home root.
    static func initialPath() -> [DashboardRoute] {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-initialRoute"), index + 1 < args.count else {
            return []
        }
        switch args[index + 1] {
        case "mealplan": return [.mealPlan]
        case "waste": return [.wasteInsights]
        default: return []
        }
    }
}

/// Inner content bound to a live store.
private struct DashboardContent: View {
    let store: DashboardStore
    var onSelectShopping: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.xl) {
                HeroSummary(summary: store.summary)
                    .padding(.horizontal, FkSpacing.lg)

                ExpiringPreviewSection(summary: store.summary)
                    .padding(.horizontal, FkSpacing.lg)

                MealPlanEntryRow()
                    .padding(.horizontal, FkSpacing.lg)

                WasteInsightsEntryRow()
                    .padding(.horizontal, FkSpacing.lg)

                if store.summary.lowStockCount > 0 {
                    LowStockEntryRow(count: store.summary.lowStockCount)
                        .padding(.horizontal, FkSpacing.lg)
                }

                ShoppingSummaryRow(
                    uncheckedCount: store.summary.uncheckedShoppingCount,
                    onTap: onSelectShopping
                )
                .padding(.horizontal, FkSpacing.lg)
            }
            .padding(.top, FkSpacing.sm)
            .padding(.bottom, FkSpacing.huge)
        }
        .background(Color.fkSurface)
        .refreshable { await store.load() }
    }
}

// MARK: - Hero

/// Tinted hero block: a headline "需要关注" count over sub-stats for 临期 and
/// 库存充足. Uses the primary brand fill with on-primary text (the blueprint's
/// hero treatment, status-bar gradient omitted as optional).
private struct HeroSummary: View {
    let summary: DashboardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.lg) {
            VStack(alignment: .leading, spacing: FkSpacing.xs) {
                Text("你的冰箱状态")
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnPrimary.opacity(0.8))

                HStack(alignment: .firstTextBaseline, spacing: FkSpacing.sm) {
                    Text("\(summary.totalItems)")
                        .font(.fkHeroStat)
                        .foregroundStyle(Color.fkOnPrimary)
                    Text("件食材")
                        .font(.fkTitleMedium)
                        .foregroundStyle(Color.fkOnPrimary.opacity(0.85))
                }
            }

            HStack(spacing: FkSpacing.sm) {
                MiniStat(
                    label: "需要处理",
                    value: summary.needsAttentionCount,
                    accent: .fkWarn
                )
                .fkEntrance(index: 0)

                MiniStat(
                    label: "已过期",
                    value: summary.expiredCount,
                    accent: .fkDanger
                )
                .fkEntrance(index: 1)

                MiniStat(
                    label: "库存充足",
                    value: summary.freshCount,
                    accent: .fkOnPrimary
                )
                .fkEntrance(index: 2)
            }
        }
        .padding(FkSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.hero, style: .continuous)
                .fill(Color.fkPrimary)
        )
        .fkCardShadow()
    }
}

/// One hero sub-stat: a big accent number over a muted label, in a translucent
/// tile (mirrors the blueprint's `_MiniStat`).
private struct MiniStat: View {
    let label: String
    let value: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.xs) {
            Text("\(value)")
                .font(.fkHeroSubStat)
                .foregroundStyle(accent)
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnPrimary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FkSpacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.chip, style: .continuous)
                .fill(Color.fkOnPrimary.opacity(0.15))
        )
    }
}

// MARK: - 临期提醒 section

private struct ExpiringPreviewSection: View {
    let summary: DashboardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.md) {
            FkSectionHeader(title: "临期提醒", count: summary.needsAttentionCount)

            if summary.hasNoExpiring {
                FkCard {
                    HStack(spacing: FkSpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.fkSuccess)
                        VStack(alignment: .leading, spacing: FkSpacing.xs) {
                            Text("暂无临期食材")
                                .font(.fkTitleMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Text("冰箱状态健康，继续保持！")
                                .font(.fkBodySmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                LazyVStack(spacing: FkSpacing.sm) {
                    ForEach(Array(summary.expiringPreview.enumerated()), id: \.element.fkListIdentityKey) { index, item in
                        FkCard {
                            IngredientRow(ingredient: item)
                        }
                        .fkEntrance(index: index)
                    }
                }

                NavigationLink(value: DashboardRoute.expiring) {
                    HStack {
                        Text("查看全部")
                            .font(.fkLabelLarge)
                            .foregroundStyle(Color.fkPrimary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.fkPrimary)
                    }
                    .padding(.vertical, FkSpacing.md)
                    .padding(.horizontal, FkSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                            .fill(Color.fkPrimarySoft)
                    )
                }
                .buttonStyle(.fkPressable)
            }
        }
    }
}

// MARK: - 膳食计划 entry

/// Tappable card that pushes `MealPlanView` (the weekly meal-plan calendar) via
/// the Dashboard's `DashboardRoute`. The only meal-plan touchpoint on 首页.
private struct MealPlanEntryRow: View {
    var body: some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("膳食计划")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text("规划这一周吃什么")
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }
}

// MARK: - 减废统计 entry

/// Tappable card that pushes `WasteInsightsView` (the waste-reduction stats
/// screen) via the Dashboard's `DashboardRoute`. Mirrors `MealPlanEntryRow`.
private struct WasteInsightsEntryRow: View {
    var body: some View {
        NavigationLink(value: DashboardRoute.wasteInsights) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("减废统计")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text("看看你的食材用掉率")
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }
}

// MARK: - 库存不足 entry

/// Tappable card that pushes `LowStockView` (常买补货) via the Dashboard's
/// `DashboardRoute`. Mirrors `MealPlanEntryRow`; only rendered when there are
/// low-stock candidates (the caller gates on `lowStockCount > 0`).
private struct LowStockEntryRow: View {
    let count: Int

    var body: some View {
        NavigationLink(value: DashboardRoute.lowStock) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("库存不足")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text("\(count) 项常买缺货")
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }
}

// MARK: - 购物清单 summary

/// Summary row that switches to the 购物 tab. Shows the unchecked count.
private struct ShoppingSummaryRow: View {
    let uncheckedCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FkCard {
                HStack(spacing: FkSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.fkPrimarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "cart.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fkPrimaryContainer)
                    }

                    VStack(alignment: .leading, spacing: FkSpacing.xs) {
                        Text("购物清单")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Text(subtitle)
                            .font(.fkBodySmall)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                    }

                    Spacer(minLength: FkSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .buttonStyle(.fkPressable)
    }

    private var subtitle: String {
        uncheckedCount > 0 ? "还有 \(uncheckedCount) 项待购买" : "清单已全部完成"
    }
}
