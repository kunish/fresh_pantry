import Foundation

/// Holds the integer id of a tapped local notification (临期提醒 / 每日汇总)
/// until the Dashboard can deep-link to the 临期 screen.
///
/// Producer = `NotificationService.onTap` (wired in `AppDependencies.init`);
/// consumer = `DashboardView` (its `.task(id: pendingTap)` consumes and pushes
/// `DashboardRoute.expiring`). `RootView` only OBSERVES `pendingTap` to switch
/// to the 首页 tab — it must NOT consume, or the Dashboard would never see the
/// intent. Mirrors the `RecipeImportRouter` pending/consume/clear pattern.
///
/// The id is stored (not just a flag) to leave room for per-item deep links;
/// today both scheduled notification kinds land on the same 临期 list.
///
/// COLD-START TIMING: when a notification tap launches the app,
/// `AppDependencies.init` installs the center delegate + tap wiring before any
/// view exists, so `didReceive` may arrive before OR after `RootView` /
/// `DashboardView` appear. Consumers must handle both orders — `.task(id:)`
/// (fires on appear AND on id change) covers both; a bare `.onChange` alone
/// would miss the captured-before-appear case.
@Observable
@MainActor
final class NotificationTapRouter {
    /// The tapped notification's id awaiting consumption; nil when none pending.
    private(set) var pendingTap: Int?

    func capture(id: Int) {
        pendingTap = id
    }

    /// One-shot read: returns the pending id and clears it. Discardable because
    /// today's only consumer routes to the same 临期 screen regardless of id.
    @discardableResult
    func consume() -> Int? {
        let value = pendingTap
        pendingTap = nil
        return value
    }

    func clear() { pendingTap = nil }
}
