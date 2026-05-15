import 'package:shared_preferences/shared_preferences.dart';

class BackupService {
  BackupService._();

  static const int backupVersion = 1;

  /// User-data SharedPreferences keys that are included in backups.
  /// Cache keys (`food_details_cache`, `recipe_details_cache`) are intentionally
  /// excluded — they regenerate and would bloat the blob.
  static const List<String> userDataKeys = [
    'inventory_items',
    'add_history',
    'shopping_items',
    'custom_recipes',
    'ai_settings_v1',
  ];

  static Map<String, dynamic> exportToMap(SharedPreferences prefs) {
    final data = <String, dynamic>{};
    for (final key in userDataKeys) {
      final value = prefs.getString(key);
      if (value != null) data[key] = value;
    }
    return {
      'version': backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
  }
}
