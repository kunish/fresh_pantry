import 'sync_operation.dart';
import 'sync_retry_policy.dart';

List<Map<String, dynamic>> visibleRemoteRows(
  Iterable<Map<String, dynamic>> rows,
) {
  return rows
      .where((row) => row['deletedAt'] == null && row['deleted_at'] == null)
      .toList(growable: false);
}

abstract class RemoteSyncGateway {
  Future<Set<String>> pushOperations(List<SyncOperation> operations);
}

/// Outbox read surface the coordinator depends on, so retry logic can be unit
/// tested without binding to Drift. [SyncOutboxRepo] implements this.
abstract class OutboxReader {
  List<SyncOperation> loadPending();
  Future<void> removeAcknowledged(Set<String> operationIds);
}

class SyncCoordinator {
  SyncCoordinator({
    required OutboxReader outbox,
    required RemoteSyncGateway remote,
    this.retry = const SyncRetryPolicy(),
  }) : _outbox = outbox,
       _remote = remote;

  final OutboxReader _outbox;
  final RemoteSyncGateway _remote;
  final SyncRetryPolicy retry;

  Future<void>? _inFlight;
  bool _rerunRequested = false;

  /// Pushes the queued outbox operations without overlapping runs.
  ///
  /// Invoked unawaited after every enqueue and during startup, so concurrent
  /// callers must be coalesced: overlapping the snapshot -> push -> remove
  /// cycle would double-push the same operations (a second run reads a stale
  /// snapshot that still contains operations the first run is acknowledging).
  ///
  /// Callers that arrive while a run is in flight are joined to it, and exactly
  /// one trailing run is scheduled afterwards so operations enqueued mid-run
  /// (which the in-flight snapshot missed) are still pushed promptly.
  Future<void> pushPending() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _rerunRequested = true;
      return inFlight;
    }
    return _start();
  }

  Future<void> _start() {
    final run = _pushPending().whenComplete(() {
      _inFlight = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        _start();
      }
    });
    _inFlight = run;
    return run;
  }

  Future<void> _pushPending() async {
    final pending = _outbox.loadPending();
    if (pending.isEmpty) return;

    for (var attempt = 1; attempt <= retry.maxAttempts; attempt++) {
      try {
        final acknowledged = await _remote.pushOperations(pending);
        await _outbox.removeAcknowledged(acknowledged);
        return;
      } catch (error) {
        final lastAttempt = attempt == retry.maxAttempts;
        if (lastAttempt || !isTransientSyncError(error)) {
          // Permanent error or retries exhausted: leave ops in the outbox to be
          // retried on the next trigger (reconnect / foreground / background).
          return;
        }
        await Future<void>.delayed(retry.delayFor(attempt));
      }
    }
  }
}
