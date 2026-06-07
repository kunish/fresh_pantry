import 'package:drift/drift.dart';

import '../models/meal_plan_entry.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

/// Local persistence for weekly meal-plan entries, scoped by household.
///
/// Mirrors [CustomRecipeRepo]: a one-shot hydrated seed keeps the notifier's
/// `build()` synchronous, while household switches reload via [loadAllFor].
class MealPlanRepo {
  MealPlanRepo(this._db);

  final AppDatabase _db;
  List<MealPlanEntry>? _hydratedSeed;

  /// Pre-read seed (injected by main.dart) so the notifier's `build()` can stay
  /// synchronous while reads from Drift are async.
  void hydrate(List<MealPlanEntry> seed) => _hydratedSeed = seed;

  /// Returns the hydrated seed once; falls back to empty when none is set
  /// (household switches load via the async [loadAllFor]).
  List<MealPlanEntry> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  Future<List<MealPlanEntry>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.mealPlanEntries)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final entries = <MealPlanEntry>[];
    for (final row in rows) {
      try {
        final entry = mealPlanFromRow(row);
        if (entry.id.isNotEmpty && entry.recipeId.isNotEmpty) {
          entries.add(entry);
        }
      } catch (_) {
        // skip malformed (e.g. missing/unparseable date)
      }
    }
    return entries;
  }

  /// 删除某 household 作用域的全部行(接管本地数据后清除 `''` 原始行)。
  Future<void> deleteHouseholdScope(String householdId) {
    return (_db.delete(_db.mealPlanEntries)
          ..where((t) => t.householdId.equals(householdId)))
        .go();
  }

  Future<void> saveEntries(String householdId, List<MealPlanEntry> entries) {
    return _db.transaction(() async {
      await (_db.delete(_db.mealPlanEntries)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.mealPlanEntries,
          entries
              .where((e) => e.id.isNotEmpty && e.recipeId.isNotEmpty)
              .map((e) => mealPlanCompanionFor(householdId, e)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }
}
