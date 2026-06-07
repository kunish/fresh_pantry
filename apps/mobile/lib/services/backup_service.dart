import 'dart:convert';

import '../models/ai_settings.dart';
import '../models/ingredient.dart';
import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';

class BackupVersionException implements Exception {
  const BackupVersionException(this.message);
  final String message;
  @override
  String toString() => 'BackupVersionException: $message';
}

/// The full set of user data a backup captures, as typed domain models.
///
/// This is the boundary between the pure codec ([BackupService]) and the
/// orchestration that reads/writes the live stores (`BackupController`). Cache
/// data (e.g. food-details lookups) is intentionally excluded — it regenerates
/// and would bloat the blob.
class BackupData {
  const BackupData({
    required this.inventory,
    required this.addHistory,
    required this.shopping,
    required this.customRecipes,
    required this.mealPlan,
    this.aiSettings,
  });

  final List<Ingredient> inventory;

  /// Add-history frequency memory kept as its raw map shape (name -> payload);
  /// it has no dedicated domain model and round-trips verbatim.
  final Map<String, dynamic> addHistory;
  final List<ShoppingItem> shopping;
  final List<Recipe> customRecipes;
  final List<MealPlanEntry> mealPlan;
  final AiSettings? aiSettings;
}

/// Pure (de)serialization for backup blobs — no storage, network, or Riverpod
/// access. It converts [BackupData] (live domain models) to/from a versioned,
/// pretty-printed JSON envelope. The orchestration that reads the live stores
/// on export and writes them on import lives in `BackupController`.
///
/// Version 2 stores structured domain-model lists. Version 1 stored raw
/// SharedPreferences string blobs keyed by legacy keys; after the Drift
/// migration those keys are no longer the source of truth, so v1 export/import
/// silently lost data. v2 reads/writes the live Drift-backed stores instead.
class BackupService {
  BackupService._();

  static const int backupVersion = 2;

  /// Serializes live app data into a versioned, pretty-printed JSON blob.
  static String encode(BackupData data) {
    final payload = <String, dynamic>{
      'inventory': data.inventory.map((i) => i.toJson()).toList(),
      'addHistory': data.addHistory,
      'shopping': data.shopping.map((s) => s.toJson()).toList(),
      'customRecipes': data.customRecipes.map((r) => r.toJson()).toList(),
      'mealPlan': data.mealPlan.map((e) => e.toJson()).toList(),
      if (data.aiSettings != null) 'aiSettings': data.aiSettings!.toJson(),
    };
    final envelope = <String, dynamic>{
      'version': backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': payload,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Parses and structurally validates a backup blob into typed [BackupData].
  ///
  /// Throws [BackupVersionException] for a missing/unsupported version and
  /// [FormatException] for malformed JSON or wrong payload shapes. Because all
  /// parsing happens here before any caller writes, a failed decode can never
  /// partially overwrite existing data.
  static BackupData decode(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      throw const FormatException('Backup blob is not valid JSON');
    }
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Backup blob is not a JSON object');
    }
    final version = root['version'];
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
    final data = root['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Backup data is not a JSON object');
    }
    return BackupData(
      inventory: _parseList(data, 'inventory', Ingredient.fromJson),
      addHistory: _parseMap(data, 'addHistory'),
      shopping: _parseList(data, 'shopping', ShoppingItem.fromJson),
      customRecipes: _parseList(data, 'customRecipes', Recipe.fromJson),
      mealPlan: _parseList(data, 'mealPlan', MealPlanEntry.fromJson),
      aiSettings: _parseAiSettings(data),
    );
  }

  static List<T> _parseList<T>(
    Map<String, dynamic> data,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = data[key];
    if (raw == null) return const [];
    if (raw is! List) {
      throw FormatException('Backup payload for "$key" must be a JSON list');
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }

  static Map<String, dynamic> _parseMap(Map<String, dynamic> data, String key) {
    final raw = data[key];
    if (raw == null) return const {};
    if (raw is! Map<String, dynamic>) {
      throw FormatException('Backup payload for "$key" must be a JSON object');
    }
    return raw;
  }

  static AiSettings? _parseAiSettings(Map<String, dynamic> data) {
    final raw = data['aiSettings'];
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Backup payload for "aiSettings" must be a JSON object',
      );
    }
    return AiSettings.fromJson(raw);
  }
}
