import 'dart:convert';
import '../models/recipe.dart';
import 'storage_adapter.dart';

class CustomRecipeRepo {
  static const storageKey = 'custom_recipes';

  final StorageAdapter _adapter;
  List<Recipe>? _hydratedSeed;

  CustomRecipeRepo(this._adapter);

  void hydrate(List<Recipe> seed) {
    _hydratedSeed = seed;
  }

  List<Recipe> loadAll() {
    if (_hydratedSeed != null) {
      final result = _hydratedSeed!;
      _hydratedSeed = null;
      return result;
    }
    final saved = _adapter.read(storageKey);
    if (saved == null) return [];

    final decoded = _decodeListOrNull(saved);
    // Top-level blob present but not a list: salvage nothing rather than let an
    // empty result auto-overwrite the still-intact stored JSON.
    if (decoded == null) return [];

    // Parse item-by-item: skip only individual bad entries, keep the rest.
    final recipes = <Recipe>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      try {
        final recipe = Recipe.fromJson(Map<String, dynamic>.from(entry));
        if (recipe.id.isNotEmpty && recipe.name.isNotEmpty) {
          recipes.add(recipe);
        }
      } catch (_) {
        // Skip this malformed entry only; keep already-parsed recipes.
      }
    }
    return recipes;
  }

  List<dynamic>? _decodeListOrNull(String source) {
    try {
      final decoded = json.decode(source);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void saveRecipes(List<Recipe> recipes) {
    _adapter.write(
      storageKey,
      json.encode(recipes.map((recipe) => recipe.toJson()).toList()),
    );
  }
}
