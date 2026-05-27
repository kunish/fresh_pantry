import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder_settings.dart';
import 'storage_service_provider.dart';

const reminderSettingsStorageKey = 'reminder_settings_v1';

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(reminderSettingsStorageKey);
    if (raw == null) return const ReminderSettings();
    try {
      return ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReminderSettings();
    }
  }

  Future<void> set(ReminderSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(reminderSettingsStorageKey, jsonEncode(next.toJson()));
  }

  Future<void> update({
    bool? remindD1,
    bool? remindD3,
    bool? remindD7,
    bool? remindDaily,
  }) =>
      set(state.copyWith(
        remindD1: remindD1,
        remindD3: remindD3,
        remindD7: remindD7,
        remindDaily: remindDaily,
      ));
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);
