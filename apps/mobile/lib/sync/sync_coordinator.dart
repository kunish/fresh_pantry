import 'sync_operation.dart';
import 'sync_outbox_repo.dart';

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

class SyncCoordinator {
  SyncCoordinator({
    required SyncOutboxRepo outbox,
    required RemoteSyncGateway remote,
  }) : _outbox = outbox,
       _remote = remote;

  final SyncOutboxRepo _outbox;
  final RemoteSyncGateway _remote;

  Future<void> pushPending() async {
    final pending = _outbox.loadPending();
    if (pending.isEmpty) return;

    final acknowledged = await _remote.pushOperations(pending);
    await _outbox.removeAcknowledged(acknowledged);
  }
}
