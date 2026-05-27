import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/reminder_settings.dart';

void main() {
  test('default values match historical local-state defaults', () {
    const s = ReminderSettings();
    expect(s.remindD1, isTrue);
    expect(s.remindD3, isTrue);
    expect(s.remindD7, isFalse);
    expect(s.remindDaily, isTrue);
  });

  test('copyWith preserves other fields', () {
    const s = ReminderSettings();
    final s2 = s.copyWith(remindD7: true);
    expect(s2.remindD7, isTrue);
    expect(s2.remindD1, isTrue);
  });

  test('toJson / fromJson round-trip', () {
    const s = ReminderSettings(remindD1: false, remindD7: true);
    final json = s.toJson();
    final restored = ReminderSettings.fromJson(json);
    expect(restored, s);
  });

  test('fromJson tolerates missing keys (returns default for them)', () {
    final s = ReminderSettings.fromJson({'remindD7': true});
    expect(s.remindD7, isTrue);
    expect(s.remindD1, isTrue, reason: 'missing → default');
  });

  test('enabledOffsetDays returns sorted list of enabled D-offsets', () {
    const s = ReminderSettings(remindD1: true, remindD3: false, remindD7: true);
    expect(s.enabledOffsetDays, [7, 1]);
  });
}
