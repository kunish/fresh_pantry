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
    /// it with the OS: cancels the previously-scheduled ids, schedules the new
    /// set (capped to the OS pending limit), then persists the new ids. A read
    /// failure leaves existing notifications untouched rather than wiping them.
    func reschedule(householdID: String) async {
        guard let items = try? await inventory.loadAllFor(householdID) else { return }
        let next = ExpiryScheduler.compute(
            inventory: items,
            settings: reminderSettings.settings,
            now: Date()
        )
        await service.syncAll(next, previousIds: idsRepo.load())
        idsRepo.save(next.map(\.id))
    }
}
