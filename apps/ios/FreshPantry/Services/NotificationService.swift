import UserNotifications

/// `@MainActor` wrapper over `UNUserNotificationCenter`: permission request /
/// check, calendar-trigger scheduling, and sync/cancel of local expiry
/// notifications. Ported from `lib/services/notification_service.dart`.
///
/// No-ops until `permissionGranted` is true (mirrors the Flutter service); uses
/// `String(id)` request identifiers so cancel/sync line up with the integer ids
/// `ExpiryScheduler` produces. Every OS call is `try?`-guarded so a denied
/// permission or a malformed request can never crash the app.
@MainActor
final class NotificationService: NSObject {
    /// iOS only keeps the soonest 64 pending local notifications; anything past
    /// that is silently dropped by the OS. `syncAll` enforces this cap.
    static let pendingCap = 64

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    /// Tap handler, invoked with the integer id parsed from the request
    /// identifier. Set via `setOnTap` after the center delegate is installed.
    /// Explicitly `@MainActor`: it is always invoked from `handleTap` on the
    /// main actor, and the wiring closure captures main-actor state.
    private var onTap: (@MainActor (Int) -> Void)?

    private(set) var isInitialized = false
    private(set) var permissionGranted = false

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current
    ) {
        self.center = center
        self.calendar = calendar
        super.init()
        center.delegate = self
        isInitialized = true
    }

    /// Registers a tap handler. Wired by `AppDependencies` to
    /// `NotificationTapRouter.capture`, so a tapped expiry notification
    /// deep-links into the 临期 screen.
    func setOnTap(_ handler: @escaping @MainActor (Int) -> Void) {
        onTap = handler
    }

    /// Core of the delegate's `didReceive`, extracted so tests can drive the
    /// tap chain without forging a `UNNotificationResponse`: forwards the
    /// tapped notification's integer id to the registered handler.
    func handleTap(id: Int) {
        onTap?(id)
    }

    // MARK: Permission

    /// Asks the OS for permission, then refreshes + returns the granted state.
    @discardableResult
    func requestPermission() async -> Bool {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        return await checkPermission()
    }

    /// Queries the current authorization without prompting; provisional counts
    /// as granted (quiet delivery still schedules).
    @discardableResult
    func checkPermission() async -> Bool {
        let settings = await center.notificationSettings()
        permissionGranted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        return permissionGranted
    }

    // MARK: Scheduling

    /// Schedules a single notification. Expiry items fire once at their exact
    /// local date/time (skipped if already past); the daily summary fires
    /// repeating at the user-chosen reminder time. No-op until permission is
    /// granted.
    func schedule(_ n: ScheduledNotification) async {
        guard permissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default

        let trigger: UNCalendarNotificationTrigger
        switch n.kind {
        case .expiry:
            guard n.scheduledAt > Date() else { return } // past — skip
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: n.scheduledAt
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .dailySummary:
            // Repeat daily at the hour/minute carried by `scheduledAt` (computed
            // by ExpiryScheduler from the reminder settings) — the single source
            // of truth for the delivery time; no global constant to drift from.
            let components = calendar.dateComponents([.hour, .minute], from: n.scheduledAt)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        let request = UNNotificationRequest(
            identifier: String(n.id),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    /// Replaces the scheduled set: cancels `previousIds`, then schedules `next`.
    ///
    /// Respects the iOS 64-pending cap: keeps the soonest expiry items (sorted
    /// by `scheduledAt`) up to `pendingCap - 1` and always keeps the daily
    /// summary, so the total scheduled is ≤ 64. No-op until ready.
    func syncAll(_ next: [ScheduledNotification], previousIds: [Int]) async {
        guard permissionGranted else { return }
        center.removePendingNotificationRequests(withIdentifiers: previousIds.map(String.init))

        let dailySummaries = next.filter { $0.kind == .dailySummary }
        let expiries = next
            .filter { $0.kind == .expiry }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .prefix(Self.pendingCap - dailySummaries.count)

        for n in dailySummaries { await schedule(n) }
        for n in expiries { await schedule(n) }
    }

    /// Cancels all previously scheduled notifications (sign-out / disable).
    func cancelAll(previousIds: [Int]) async {
        center.removePendingNotificationRequests(withIdentifiers: previousIds.map(String.init))
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Surfaces a tapped notification's integer id to `onTap`. Minimal + safe:
    /// a non-integer identifier is ignored.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Acknowledge the system synchronously, then hop to the main actor for
        // the tap handler (`completionHandler` is not Sendable — never captured
        // into the Task).
        let identifier = response.notification.request.identifier
        completionHandler()
        guard let id = Int(identifier) else { return }
        Task { @MainActor [weak self] in self?.handleTap(id: id) }
    }
}
