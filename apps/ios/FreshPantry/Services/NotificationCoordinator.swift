import Foundation

/// Ties expiry-reminder scheduling together: reads the current inventory +
/// reminder settings, computes the desired notification set via
/// `ExpiryScheduler`, and reconciles it against the OS through
/// `NotificationService`, persisting the scheduled ids for the next resync.
///
/// `@MainActor` because it drives the `@MainActor` `NotificationService` and
/// `ReminderSettingsStore`. The pure scheduling math lives in `ExpiryScheduler`;
/// this layer is just I/O wiring.
@MainActor
final class NotificationCoordinator {
    private let service: NotificationService
    private let idsRepo: ScheduledNotificationIdsRepo
    private let inventory: InventoryRepository
    private let reminderSettings: ReminderSettingsStore

    init(
        service: NotificationService,
        idsRepo: ScheduledNotificationIdsRepo,
        inventory: InventoryRepository,
        reminderSettings: ReminderSettingsStore
    ) {
        self.service = service
        self.idsRepo = idsRepo
        self.inventory = inventory
        self.reminderSettings = reminderSettings
    }

    /// Whether the OS has granted notification permission (drives the Settings
    /// affordance). Refreshed from the OS without prompting.
    @discardableResult
    func refreshPermission() async -> Bool {
        await service.checkPermission()
    }

    /// Prompts for permission, then reschedules so a freshly-granted permission
    /// takes effect immediately. Returns the granted state.
    @discardableResult
    func requestPermission(householdID: String) async -> Bool {
        let granted = await service.requestPermission()
        if granted { await reschedule(householdID: householdID) }
        return granted
    }

    /// Recomputes the desired notification set for the household and reconciles
    /// it with the OS: schedules the new set first (capped to the OS pending
    /// limit), then cancels only the obsolete diff, then persists the new ids —
    /// suspension mid-way can at worst leave one extra stale reminder. A read
    /// failure leaves existing notifications untouched rather than wiping them.
    ///
    /// Refreshes the real OS permission first (no prompt): the service's
    /// in-memory flag resets to false on every launch, so without this every
    /// post-launch reschedule would be a silent no-op. Bails before touching
    /// the ids ledger when ungranted — and only persists it after `syncAll`
    /// confirms it ran — because a ledger written around a no-op sync records
    /// ids the OS never received, leaving the actually-pending requests
    /// uncancellable forever.
    ///
    /// Ids dropped from the desired set ONLY because their slot time is already
    /// past today (the reminder time just moved earlier) are retained instead of
    /// cancelled — their pending request still fires once at the old time. See
    /// `ExpiryScheduler.partitionPreviousIds`.
    func reschedule(householdID: String) async {
        guard await service.checkPermission() else { return }
        guard let items = try? await inventory.loadAllFor(householdID) else { return }
        let settings = reminderSettings.settings
        // Same derivation as the 首页 库存不足 card (bought ≥3 times, none in
        // stock), so the daily summary honors the Settings copy 「包含临期 +
        // 库存不足」. Snapshot fixed at schedule time; every reschedule refreshes it.
        let lowStock = LowStockStore(repository: inventory, householdID: householdID)
        await lowStock.load()
        let next = ExpiryScheduler.compute(
            inventory: items,
            settings: settings,
            now: Date(),
            lowStockCount: lowStock.items.count
        )
        let (cancel, retain) = ExpiryScheduler.partitionPreviousIds(
            idsRepo.load(),
            next: next,
            inventory: items,
            settings: settings
        )
        guard await service.syncAll(next, previousIds: cancel) else { return }
        idsRepo.save(next.map(\.id) + retain)
    }
}
