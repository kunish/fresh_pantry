import 'package:drift/drift.dart';

import '../models/recipe.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

class CustomRecipeRepo {
  CustomRecipeRepo(this._db);

  /// Legacy SharedPreferences key, retained for the one-time blob migration and
  /// the backup/export service which still read/write the prefs snapshot.
  static const storageKey = 'custom_recipes';

  final AppDatabase _db;
  List<Recipe>? _hydratedSeed;

  /// Pre-read seed (injected by main.dart) so the notifier's `build()` can stay
  /// synchronous while reads from Drift are async.
  void hydrate(List<Recipe> seed) => _hydratedSeed = seed;

  /// Returns the hydrated seed once; falls back to empty when none is set
  /// (household switches load via the async [loadAllFor]).
  List<Recipe> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  Future<List<Recipe>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.customRecipes)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final recipes = <Recipe>[];
    for (final row in rows) {
      try {
        final recipe = recipeFromRow(row);
        if (recipe.id.isNotEmpty && recipe.name.isNotEmpty) recipes.add(recipe);
      } catch (_) {
        // skip malformed
      }
    }
    return recipes;
  }

  /// 删除某 household 作用域的全部行(接管本地数据后清除 `''` 原始行)。
  Future<void> deleteHouseholdScope(String householdId) {
    return (_db.delete(_db.customRecipes)
          ..where((t) => t.householdId.equals(householdId)))
        .go();
  }

  Future<void> saveRecipes(String householdId, List<Recipe> recipes) {
    return _db.transaction(() async {
      await (_db.delete(_db.customRecipes)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.customRecipes,
          recipes
              .where((r) => r.id.isNotEmpty && r.name.isNotEmpty)
              .map((r) => recipeCompanionFor(householdId, r)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }
}
