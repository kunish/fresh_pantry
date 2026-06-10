import Testing
@testable import FreshPantry

/// Semantics of the notification-tap deep-link router: capture stores the
/// tapped id, consume is one-shot, clear discards without reading.
@MainActor
struct NotificationTapRouterTests {
    @Test func startsWithNoPendingTap() {
        let router = NotificationTapRouter()
        #expect(router.pendingTap == nil)
    }

    @Test func captureStoresTappedId() {
        let router = NotificationTapRouter()
        router.capture(id: 42)
        #expect(router.pendingTap == 42)
    }

    @Test func captureOverwritesPreviousPendingTap() {
        let router = NotificationTapRouter()
        router.capture(id: 1)
        router.capture(id: 2)
        #expect(router.pendingTap == 2)
    }

    @Test func consumeReturnsIdOnceThenNil() {
        let router = NotificationTapRouter()
        router.capture(id: 7)
        #expect(router.consume() == 7)
        #expect(router.pendingTap == nil)
        #expect(router.consume() == nil)
    }

    @Test func clearDiscardsPendingTap() {
        let router = NotificationTapRouter()
        router.capture(id: 9)
        router.clear()
        #expect(router.pendingTap == nil)
    }
}

/// Wiring test: `AppDependencies` must install the notification tap handler so
/// a tapped notification's id lands in `notificationTapRouter` — the half the
/// original implementation left dangling (`setOnTap` was never called).
/// Drives `NotificationService.handleTap` (the extracted, testable core of the
/// delegate's `didReceive`) instead of forging a `UNNotificationResponse`.
@MainActor
struct NotificationTapWiringTests {
    @Test func tappedNotificationIdReachesRouter() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container)

        dependencies.notificationService.handleTap(id: 123)

        #expect(dependencies.notificationTapRouter.pendingTap == 123)
    }

    @Test func laterTapOverwritesUnconsumedRouterId() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let dependencies = AppDependencies(modelContainer: container)

        dependencies.notificationService.handleTap(id: 1)
        dependencies.notificationService.handleTap(id: 2)

        #expect(dependencies.notificationTapRouter.pendingTap == 2)
    }
}
