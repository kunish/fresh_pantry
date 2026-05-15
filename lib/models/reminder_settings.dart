import 'package:flutter/foundation.dart';

@immutable
class ReminderSettings {
  const ReminderSettings({
    this.remindD1 = true,
    this.remindD3 = true,
    this.remindD7 = false,
    this.remindDaily = true,
  });

  final bool remindD1;
  final bool remindD3;
  final bool remindD7;
  final bool remindDaily;

  /// Returns the enabled D-N offsets sorted earliest-first (largest N first).
  /// Used by ExpiryScheduler to know which per-item reminders to schedule.
  List<int> get enabledOffsetDays => [
        if (remindD7) 7,
        if (remindD3) 3,
        if (remindD1) 1,
      ];

  ReminderSettings copyWith({
    bool? remindD1,
    bool? remindD3,
    bool? remindD7,
    bool? remindDaily,
  }) =>
      ReminderSettings(
        remindD1: remindD1 ?? this.remindD1,
        remindD3: remindD3 ?? this.remindD3,
        remindD7: remindD7 ?? this.remindD7,
        remindDaily: remindDaily ?? this.remindDaily,
      );

  Map<String, dynamic> toJson() => {
        'remindD1': remindD1,
        'remindD3': remindD3,
        'remindD7': remindD7,
        'remindDaily': remindDaily,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        remindD1: j['remindD1'] as bool? ?? true,
        remindD3: j['remindD3'] as bool? ?? true,
        remindD7: j['remindD7'] as bool? ?? false,
        remindDaily: j['remindDaily'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderSettings &&
          remindD1 == other.remindD1 &&
          remindD3 == other.remindD3 &&
          remindD7 == other.remindD7 &&
          remindDaily == other.remindDaily;

  @override
  int get hashCode => Object.hash(remindD1, remindD3, remindD7, remindDaily);
}
