import 'dart:async';
import 'dart:io';

class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayFor(int attempt) {
    final ms = baseDelay.inMilliseconds * (1 << (attempt - 1));
    return Duration(milliseconds: ms.clamp(0, maxDelay.inMilliseconds));
  }
}

/// Transient = worth retrying (network/timeout). Everything else is permanent
/// (validation / auth) — retrying would just spin.
bool isTransientSyncError(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is HttpException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('connection') ||
      text.contains('network');
}
