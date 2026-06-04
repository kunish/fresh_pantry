import 'dart:convert';

import 'storage_adapter.dart';

/// Persists the set of OS notification ids scheduled in the current session, so
/// a later resync can cancel the ones it no longer needs.
///
/// Thin [StorageAdapter] wrapper that decodes defensively — a missing or
/// malformed blob yields an empty list rather than throwing.
class ScheduledNotificationIdsRepo {
  static const storageKey = 'notification_sync_scheduled_ids_v1';

  final StorageAdapter _adapter;

  ScheduledNotificationIdsRepo(this._adapter);

  List<int> load() {
    final raw = _adapter.read(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<int>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<int> ids) {
    return _adapter.write(storageKey, jsonEncode(ids));
  }
}
