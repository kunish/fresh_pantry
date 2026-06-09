import Foundation

/// A concrete OS-level scheduled local notification descriptor.
/// `id` is an integer (not a string); `kind` drives identifier namespacing.
struct ScheduledNotification: Equatable, Sendable {
    var id: Int
    var title: String
    var body: String
    var scheduledAt: Date
    var kind: ScheduledNotificationKind

    init(
        id: Int,
        title: String,
        body: String,
        scheduledAt: Date,
        kind: ScheduledNotificationKind = .expiry
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.scheduledAt = scheduledAt
        self.kind = kind
    }
}
