import Foundation

extension Notification.Name {
    /// Posted by `WidgetPendingToggleDrainer` after a drain actually FLIPPED a
    /// row — the foreground 购物 list (and the 首页 购物 tile) are DIFFERENT
    /// `ShoppingStore` instances that know nothing of this cross-process write,
    /// so without the pulse they keep showing their pre-toggle snapshot until a
    /// manual pull / household switch / remote-sync apply (the exact mirror of
    /// `.intentDidDrainShoppingAdd`).
    static let widgetDidDrainShoppingToggle = Notification.Name("fresh_pantry.widget.didDrainShoppingToggle")
}

/// **app 侧**:把 widget 攒下的「待落库勾选」真正落库。widget 进程只 append 了
/// itemID 到 App Group 队列(不碰 SwiftData);这里在主进程经 `ShoppingToggleService`
/// 逐条翻转 store + 记 outbox,再用权威数据重写展示快照(覆盖 widget 的乐观补丁)。
/// 在启动/家庭就绪/回前台时调用,与 `IntentAddDrainer` 同位。
///
/// `@MainActor`(与 `IntentAddDrainer` 一致):它读 `@MainActor AppDependencies` 的
/// 标量、bump `SyncSession` 的 revision、从主线程 post 刷新脉冲;重活(SwiftData 写、
/// outbox 推送)都在 `await` 的非隔离 func / actor 上跑,不阻塞主线程。
@MainActor
enum WidgetPendingToggleDrainer {
    /// `pending` defaults to draining (read + clear) the App Group queue — the
    /// production behavior; tests inject an explicit list so they never touch the
    /// shared cross-process file (mirrors `IntentAddDrainer`'s injected queue).
    /// `center` is injectable for the same reason its sibling drainer's is.
    static func drain(
        dependencies: AppDependencies,
        pending: [String] = WidgetPendingToggleStore.drain(),
        center: NotificationCenter = .default
    ) async {
        guard !pending.isEmpty else { return }
        var didWrite = false
        for id in pending {
            if await ShoppingToggleService.toggle(
                container: dependencies.modelContainer,
                householdID: dependencies.householdID,
                itemID: id,
                clientID: dependencies.syncSession.clientId,
                now: .now
            ) {
                didWrite = true
            }
        }
        await WidgetSnapshotPublisher.publish(
            container: dependencies.modelContainer,
            householdID: dependencies.householdID
        )
        // Pulse only on a real flip — a drain that matched no row (the queued item
        // was deleted before foreground) changed nothing, so the visible list has
        // nothing new to show and a reload would be wasted work.
        guard didWrite else { return }
        // Reload the visible list FIRST (local store already holds the flip — fast).
        center.post(name: .widgetDidDrainShoppingToggle, object: nil)
        // Then sync the just-enqueued outbox ops and converge the banner / 待同步
        // badges, exactly as every in-app mutation does via SyncWriter. This path
        // enqueues to the outbox DIRECTLY (ShoppingToggleService bypasses
        // SyncWriter), so it must mirror that trailing push + pendingSyncRevision
        // bump itself — otherwise the op is never pushed promptly (it only rides
        // RootView's racy foreground push) and the count never re-reads the outbox,
        // leaving an eternal 「同步中,1 条待同步」. Household-only: a local-only flip
        // never enqueues, so there is nothing to push.
        guard !dependencies.householdID.isEmpty else { return }
        await dependencies.syncCoordinator?.pushPending()
        dependencies.syncSession.bumpPendingSyncRevision()
    }
}
