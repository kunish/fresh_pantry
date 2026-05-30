import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../sync/sync_operation.dart';
import '../sync/sync_outbox_repo.dart';
import 'custom_recipe_repo.dart';
// The drift-generated row data class is also named `ShoppingItem`, colliding
// with the model imported above. Hide it; this file only needs `AppDatabase`.
import 'drift/app_database.dart' hide ShoppingItem;
import 'inventory_repo.dart';
import 'shopping_repo.dart';

/// SharedPreferences flag marking the one-time migration as done.
const migratedFlagKey = 'drift_migrated_v1';

/// Legacy SharedPreferences keys read (and intentionally preserved) by the
/// migration. Public so tests can assert on the same single source of truth
/// instead of duplicating string literals.
const legacyInventoryKey = 'inventory_items';
const legacyShoppingKey = 'shopping_items';
const legacyRecipesKey = 'custom_recipes';
const legacyOutboxKey = 'sync_outbox_v1';
const legacyHistoryKey = 'add_history';

/// One-time import of legacy SharedPreferences blobs into Drift.
///
/// Idempotent via [migratedFlagKey]; the flag is set only after every write
/// succeeds, so a mid-flight error leaves the flag unset and lets a later run
/// retry instead of permanently dropping data. Legacy blobs are left in place
/// for one release as a rollback path. Parsing is per-entry lenient: a single
/// malformed entry is skipped while the rest are kept (mirrors repo resilience).
Future<void> migratePrefsBlobsToDrift({
  required SharedPreferences prefs,
  required AppDatabase db,
}) async {
  if (prefs.getBool(migratedFlagKey) == true) return;

  final inventory = _mapLenient(
    _decodeList(prefs.getString(legacyInventoryKey)),
    Ingredient.fromJson,
  );
  final shopping = _mapLenient(
    _decodeList(prefs.getString(legacyShoppingKey)),
    ShoppingItem.fromJson,
  );
  final recipes = _mapLenient(
    _decodeList(prefs.getString(legacyRecipesKey)),
    Recipe.fromJson,
  ).where((r) => r.id.isNotEmpty && r.name.isNotEmpty).toList();
  final ops = _mapLenient(
    _decodeList(prefs.getString(legacyOutboxKey)),
    SyncOperation.fromJson,
  );
  final history = _decodeMap(prefs.getString(legacyHistoryKey));

  // local-only 作用域 ''(与冷启动种子一致)。
  await InventoryRepo(db).saveItems('', inventory);
  await ShoppingRepo(db).saveItems('', shopping);
  await CustomRecipeRepo(db).saveRecipes('', recipes);
  await SyncOutboxRepo(db).replaceAll(ops);
  if (history.isNotEmpty) await InventoryRepo(db).saveHistory(history);

  // Flag only after all writes succeed; a mid-flight throw leaves it unset.
  await prefs.setBool(migratedFlagKey, true);
}

/// Parses each row independently; a single bad entry is skipped, the rest kept.
List<T> _mapLenient<T>(
  List<Map<String, dynamic>> rows,
  T Function(Map<String, dynamic>) parse,
) {
  final out = <T>[];
  for (final r in rows) {
    try {
      out.add(parse(r));
    } catch (_) {
      // 跳过坏条目，保留其余。
    }
  }
  return out;
}

List<Map<String, dynamic>> _decodeList(String? raw) {
  if (raw == null) return const [];
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (_) {
    return const [];
  }
}

Map<String, dynamic> _decodeMap(String? raw) {
  if (raw == null) return const {};
  try {
    final decoded = json.decode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}
