import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers/ai_settings_provider.dart' show aiSettingsStorageKey;
import '../providers/custom_recipe_provider.dart' show customRecipesStorageKey;
import '../providers/inventory_provider.dart' show kAddHistoryKey, kInventoryKey;
import '../providers/shopping_provider.dart' show kShoppingKey;

class BackupVersionException implements Exception {
  const BackupVersionException(this.message);
  final String message;
  @override
  String toString() => 'BackupVersionException: $message';
}

class BackupService {
  BackupService._();

  static const int backupVersion = 1;

  /// User-data SharedPreferences keys that are included in backups.
  /// Cache keys (`food_details_cache`, `recipe_details_cache`) are intentionally
  /// excluded — they regenerate and would bloat the blob.
  static const List<String> userDataKeys = [
    kInventoryKey,
    kAddHistoryKey,
    kShoppingKey,
    customRecipesStorageKey,
    aiSettingsStorageKey,
  ];

  static String encodeToJson(Map<String, dynamic> map) {
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static Map<String, dynamic> decodeFromJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup blob is not a JSON object');
    }
    final version = decoded['version'];
    if (version is! int) {
      throw BackupVersionException(
        'Missing or invalid version (got: $version)',
      );
    }
    if (version != backupVersion) {
      throw BackupVersionException(
        'Unsupported backup version $version (expected $backupVersion)',
      );
    }
    return decoded;
  }

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
