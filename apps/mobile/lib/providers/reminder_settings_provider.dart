import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder_settings.dart';
import '../storage/reminder_settings_repo.dart';
import 'storage_service_provider.dart';

const reminderSettingsStorageKey = ReminderSettingsRepo.storageKey;

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  late ReminderSettingsRepo _repo;

  @override
  ReminderSettings build() {
    _repo = ref.read(reminderSettingsRepoProvider);
    return _repo.load();
  }

  Future<void> set(ReminderSettings next) async {
    state = next;
    await _repo.save(next);
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
