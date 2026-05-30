import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_retry_policy.dart';

class _FlakyGateway implements RemoteSyncGateway {
  _FlakyGateway(this.failuresBeforeSuccess);
  int failuresBeforeSuccess;
  int calls = 0;
  @override
  Future<Set<String>> pushOperations(List<SyncOperation> ops) async {
    calls++;
    if (failuresBeforeSuccess-- > 0) {
      throw const SocketException('offline');
    }
    return ops.map((o) => o.id).toSet();
  }
}

// 最小 outbox stub（替代 Drift，专注测重试）
class _StubOutbox implements OutboxReader {
  _StubOutbox(this._ops);
  List<SyncOperation> _ops;
  @override
  List<SyncOperation> loadPending() => _ops;
  @override
  Future<void> removeAcknowledged(Set<String> ids) async {
    _ops = _ops.where((o) => !ids.contains(o.id)).toList();
  }
}

SyncOperation _op(String id) => SyncOperation(
      id: id, householdId: 'h1', entityType: SyncEntityType.inventoryItem,
      entityId: 'a', operation: SyncOperationType.create, patch: const {},
      clientId: 'c', createdAt: DateTime.utc(2026, 1, 1));

void main() {
  test('retries transient errors then succeeds, drains outbox', () async {
    final gw = _FlakyGateway(2);
    final outbox = _StubOutbox([_op('op1')]);
    final coord = SyncCoordinator(
      outbox: outbox,
      remote: gw,
      retry: const SyncRetryPolicy(maxAttempts: 5, baseDelay: Duration.zero),
    );
    await coord.pushPending();
    expect(gw.calls, 3); // 2 fail + 1 success
    expect(outbox.loadPending(), isEmpty);
  });

  test('gives up after maxAttempts, leaves ops in outbox', () async {
    final gw = _FlakyGateway(99);
    final outbox = _StubOutbox([_op('op1')]);
    final coord = SyncCoordinator(
      outbox: outbox,
      remote: gw,
      retry: const SyncRetryPolicy(maxAttempts: 3, baseDelay: Duration.zero),
    );
    await coord.pushPending();
    expect(gw.calls, 3);
    expect(outbox.loadPending().map((o) => o.id), ['op1']);
  });
}
