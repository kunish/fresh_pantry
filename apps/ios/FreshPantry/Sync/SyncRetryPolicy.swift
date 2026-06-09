import Foundation

/// Exponential-backoff schedule for outbox push retries, ported from
/// `lib/sync/sync_retry_policy.dart`.
///
/// The delay doubles each attempt (500ms, 1s, 2s, 4s, …) and is clamped to
/// `maxDelay`, so a long-lived offline window can't grow the wait unboundedly.
struct SyncRetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: Duration
    let maxDelay: Duration

    init(
        maxAttempts: Int = 4,
        baseDelay: Duration = .milliseconds(500),
        maxDelay: Duration = .seconds(8)
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Delay before the next retry for a 1-based `attempt`. Mirrors the Dart
    /// `baseDelay.inMilliseconds * (1 << (attempt - 1))` clamped to
    /// `[0, maxDelay]`, computed in milliseconds to match the Flutter arithmetic.
    func delayFor(attempt: Int) -> Duration {
        let baseMs = baseDelay.milliseconds
        let maxMs = maxDelay.milliseconds
        let scaledMs = baseMs * (1 << (attempt - 1))
        let clampedMs = min(max(scaledMs, 0), maxMs)
        return .milliseconds(clampedMs)
    }
}

/// Transient = worth retrying (network/timeout). Everything else is permanent
/// (validation / auth) — retrying would just spin. Mirrors the Dart
/// `isTransientSyncError`: the Dart `SocketException` / `TimeoutException` /
/// `HttpException` type checks become `URLError` network codes here, with the
/// same lowercased substring fallback as the final net.
func isTransientSyncError(_ error: Error) -> Bool {
    if let urlError = error as? URLError, transientURLErrorCodes.contains(urlError.code) {
        return true
    }
    let text = String(describing: error).lowercased()
    return text.contains("socket")
        || text.contains("timeout")
        || text.contains("timed out")
        || text.contains("connection")
        || text.contains("network")
}

/// Network-failure `URLError` codes treated as transient, standing in for the
/// Dart `SocketException` / `TimeoutException` family.
private let transientURLErrorCodes: Set<URLError.Code> = [
    .notConnectedToInternet,
    .timedOut,
    .networkConnectionLost,
    .cannotConnectToHost,
    .cannotFindHost,
    .dnsLookupFailed,
]

private extension Duration {
    /// Whole milliseconds, mirroring Dart's `Duration.inMilliseconds`. The
    /// `attoseconds` component is below ms granularity for the values used here
    /// (500ms / 8s) so truncating it loses nothing.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
