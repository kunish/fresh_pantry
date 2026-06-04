import 'dart:convert';

import '../models/reminder_settings.dart';
import 'storage_adapter.dart';

/// Persists [ReminderSettings] as a JSON blob.
///
/// Mirrors the [AiSettingsRepo] seam: a thin wrapper over a [StorageAdapter]
/// that decodes defensively — a missing or malformed blob yields defaults
/// rather than throwing. Keeps the Notifier free of raw storage + serialization.
class ReminderSettingsRepo {
  static const storageKey = 'reminder_settings_v1';

  final StorageAdapter _adapter;

  ReminderSettingsRepo(this._adapter);

  ReminderSettings load() {
    final raw = _adapter.read(storageKey);
    if (raw == null || raw.isEmpty) return const ReminderSettings();
    try {
      return ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReminderSettings();
    }
  }

  Future<void> save(ReminderSettings settings) {
    return _adapter.write(storageKey, jsonEncode(settings.toJson()));
  }
}
