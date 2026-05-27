import 'dart:convert';

import '../storage/storage_adapter.dart';
import 'sync_operation.dart';

class SyncOutboxRepo {
  SyncOutboxRepo(this._adapter);

  static const storageKey = 'sync_outbox_v1';

  final StorageAdapter _adapter;

  List<SyncOperation> loadPending() {
    try {
      return _loadPending();
    } catch (_) {
      return const [];
    }
  }

  List<SyncOperation> _loadPending() {
    final raw = _adapter.read(storageKey);
    if (raw == null) return const [];
    return _decodeOperationRows(raw).map(SyncOperation.fromJson).toList();
  }

  Future<void> enqueue(SyncOperation operation) {
    return _save([..._loadPending(), operation]);
  }

  Future<void> removeAcknowledged(Set<String> operationIds) {
    final pending = _loadPending()
        .where((operation) => !operationIds.contains(operation.id))
        .toList();
    return _save(pending);
  }

  Future<void> replaceAll(List<SyncOperation> operations) {
    return _save(operations);
  }

  Future<void> _save(List<SyncOperation> operations) {
    return _adapter.write(
      storageKey,
      json.encode(operations.map((operation) => operation.toJson()).toList()),
    );
  }
}

List<Map<String, dynamic>> _decodeOperationRows(String source) {
  final decoded = json.decode(source);
  if (decoded is! List<dynamic>) {
    throw const FormatException('Expected sync outbox JSON list');
  }

  return decoded
      .map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Expected sync outbox JSON object');
        }
        return entry;
      })
      .toList(growable: false);
}
