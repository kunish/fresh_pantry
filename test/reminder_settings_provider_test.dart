import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/reminder_settings.dart';
import 'package:fresh_pantry/providers/reminder_settings_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
}

void main() {
  test('reads defaults when prefs empty', () async {
    final c = await _container();
    final s = c.read(reminderSettingsProvider);
    expect(s, const ReminderSettings());
  });

  test('hydrates from prefs JSON', () async {
    final c = await _container(seed: {
      reminderSettingsStorageKey: '{"remindD7":true,"remindDaily":false}',
    });
    final s = c.read(reminderSettingsProvider);
    expect(s.remindD7, isTrue);
    expect(s.remindDaily, isFalse);
    expect(s.remindD1, isTrue, reason: 'default for missing');
  });

  test('set persists to prefs', () async {
    final c = await _container();
    final n = c.read(reminderSettingsProvider.notifier);
    await n.set(const ReminderSettings(remindD1: false));
    final raw = (await SharedPreferences.getInstance())
        .getString(reminderSettingsStorageKey);
    expect(raw, contains('"remindD1":false'));
  });
}
