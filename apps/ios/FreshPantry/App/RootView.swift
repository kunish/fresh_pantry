import SwiftUI

/// Root navigation surface.
///
/// Uses a `TabView` with the sidebar-adaptable style so the same declaration
/// renders as a bottom tab bar on iPhone and an adaptive sidebar/tab layout on
/// iPad. The five sections mirror the existing app's primary navigation; each
/// is a placeholder until its feature module is migrated.
struct RootView: View {
    /// The five primary sections. `rawValue` doubles as a stable selection key.
    enum Section: String, Hashable, CaseIterable {
        case home, inventory, recipes, shopping, settings
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Section = RootView.initialSelection()

    var body: some View {
        // Snapshot/test hook: `-initialRoute login` renders LoginView standalone
        // so the auth screen can be captured without driving the tab UI.
        if RootView.initialRoute() == "login" {
            NavigationStack {
                LoginView(auth: dependencies.authService)
            }
            .tint(.fkPrimary)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("首页", systemImage: "house", value: Section.home) {
                DashboardView(onSelectShopping: { selection = .shopping })
            }
            Tab("库存", systemImage: "tray.full", value: Section.inventory) {
                InventoryView()
            }
            Tab("食谱", systemImage: "book", value: Section.recipes) {
                RecipesView()
            }
            Tab("购物", systemImage: "cart", value: Section.shopping) {
                ShoppingView()
            }
            Tab("设置", systemImage: "gearshape", value: Section.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // DRIVE CONTENT SYNC: reconcile local⇄remote for the selected household.
        // Re-runs on every household switch (and once on launch); the coordinator
        // no-ops when the household is unchanged. nil in local-only mode.
        .task(id: dependencies.syncSession.selectedHouseholdId) {
            await dependencies.householdContentSync?
                .syncTo(dependencies.syncSession.selectedHouseholdId)
        }
        // FOREGROUND FLUSH + RESCHEDULE: on every return to the foreground drain
        // the outbox (the dependable push path — background sync is throttled on
        // iOS) and recompute expiry reminders so they reflect the latest
        // inventory / settings without waiting for a Settings change.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await dependencies.syncCoordinator?.pushPending() }
            Task {
                await dependencies.notificationCoordinator
                    .reschedule(householdID: dependencies.householdID)
            }
        }
        // Initial reschedule on launch (the first .active may precede this view).
        .task {
            await dependencies.notificationCoordinator
                .reschedule(householdID: dependencies.householdID)
        }
        // RESTORE SESSION ON LAUNCH: rehydrate a persisted login from the Keychain
        // so a returning member is signed in (and sync starts) without first
        // opening the login screen. No-op in local-only mode or when already
        // signed in. Runs before the auth-driven auto-select below picks the
        // household, so the households query carries the restored JWT (avoiding the
        // verify→immediate-query token-propagation race of a fresh sign-in).
        .task {
            await dependencies.authService.restore()
        }
        // AUTO-SELECT HOUSEHOLD ON SIGN-IN: mirrors Flutter's AuthGate projecting
        // the session's active household into `selectedHouseholdId`, so sync starts
        // right after login instead of only once the 家庭共享 screen is opened.
        // Re-runs whenever the signed-in identity changes (incl. nil → email).
        .task(id: dependencies.authService.signedInEmail) {
            guard dependencies.authService.signedInEmail != nil else { return }
            // Ensure the SDK session is resolved so the households query carries the
            // user JWT (else it silently runs as anon → RLS-empty → no household).
            await dependencies.clientProvider.ensureSessionReady()
            let store = HouseholdSessionStore(
                remote: dependencies.remotePantryRepository,
                session: dependencies.syncSession,
                auth: dependencies.authService,
                inventory: dependencies.inventoryRepository,
                shopping: dependencies.shoppingRepository,
                customRecipe: dependencies.customRecipeRepository,
                mealPlan: dependencies.mealPlanRepository
            )
            await store.refreshHouseholds()
        }
        #if DEBUG
        // Automation hooks for the live-sync verification (no UI typing on the
        // simulator): `-debugAuthEmail <e>` sends an OTP; `-debugAuthVerify <e>
        // -debugAuthCode <c>` verifies it and signs in (the auto-select task then
        // starts the pull). Inert unless the args are present.
        .task {
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            if let email = value("-debugAuthEmail") {
                await dependencies.authService.sendCode(email: email)
            } else if let email = value("-debugAuthVerify"), let code = value("-debugAuthCode") {
                await dependencies.authService.debugVerify(email: email, code: code)
            }
        }
        #endif
    }

    /// Honors a `-initialTab <section>` launch argument (used by UI snapshots /
    /// tests); defaults to 首页.
    private static func initialSelection() -> Section {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-initialTab"),
              index + 1 < ProcessInfo.processInfo.arguments.count,
              let section = Section(rawValue: ProcessInfo.processInfo.arguments[index + 1])
        else { return .home }
        return section
    }

    /// Honors a `-initialRoute <route>` launch argument (snapshot/test hook);
    /// `login` renders `LoginView` standalone. Returns nil otherwise.
    private static func initialRoute() -> String? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-initialRoute"),
              index + 1 < ProcessInfo.processInfo.arguments.count
        else { return nil }
        return ProcessInfo.processInfo.arguments[index + 1]
    }
}

/// Temporary stand-in shown for sections whose feature module has not yet been
/// migrated from the Flutter app. Exercises the core design-system tokens.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            VStack(spacing: FkSpacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.fkPrimary)
                Text(title)
                    .font(.fkHeadlineSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text("迁移进行中")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fkSurface)
            .navigationTitle(title)
        }
    }
}

#Preview {
    let container = try! ModelContainerFactory.makeInMemory()
    RootView()
        .modelContainer(container)
        .environment(AppDependencies(modelContainer: container))
}
