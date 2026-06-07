import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Ingredient _ing({
  required String name,
  FreshnessState state = FreshnessState.fresh,
}) => Ingredient(
  name: name,
  quantity: '1',
  unit: '个',
  imageUrl: '',
  freshnessPercent: state == FreshnessState.fresh ? 1.0 : 0.2,
  state: state,
  category: FoodCategories.other,
  storage: IconType.fridge,
);

Recipe _recipe(String id, String name, List<String> ingredientNames) => Recipe(
  id: id,
  name: name,
  category: '中餐',
  difficulty: 1,
  cookingMinutes: 10,
  description: '',
  ingredients:
      ingredientNames
          .map((n) => RecipeIngredient(name: n, quantity: '1', unit: '个'))
          .toList(),
  steps: const [],
);

Future<ProviderContainer> _container({
  required List<Ingredient> inventory,
  required List<Recipe> recipes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...testStorageOverrides(database: db, inventory: inventory),
      recipesProvider.overrideWith((ref) => Future.value(recipes)),
    ],
  );
}

void main() {
  test(
    'recipe using an expiringSoon ingredient ranks above an equal-match fresh one',
    () async {
      final inventory = [
        _ing(name: '番茄', state: FreshnessState.expiringSoon),
        _ing(name: '鸡蛋', state: FreshnessState.fresh),
        _ing(name: '黄瓜', state: FreshnessState.fresh),
      ];
      // Put the non-expiring recipe FIRST so that without the boost, a stable sort
      // would keep 'b' ahead of 'a' (both score 1.0 matched/total). The boost
      // must push 'a' (uses expiringSoon 番茄) past 'b'.
      final recipes = [
        _recipe('b', '黄瓜炒蛋', [
          '黄瓜',
          '鸡蛋',
        ]), // doesn't use expiring — listed first
        _recipe('a', '番茄炒蛋', ['番茄', '鸡蛋']), // uses expiring — listed second
      ];
      final c = await _container(inventory: inventory, recipes: recipes);
      addTearDown(c.dispose);
      // Wait for the async recipesProvider to resolve.
      await c.read(recipesProvider.future);
      final ranked = c.read(recommendedRecipesProvider);
      expect(
        ranked.first.id,
        'a',
        reason: 'expiringSoon-boost should put 番茄炒蛋 first',
      );
    },
  );

  group('recipesRankedByExpiringUse', () {
    test('ranks the dish that clears the most perishables first', () {
      final expiring = {'番茄', '青椒', '牛肉'};
      final recommended = [
        _recipe('one', '番茄炒蛋', ['番茄', '鸡蛋']), // clears 1
        _recipe('three', '番茄青椒牛肉', ['番茄', '青椒', '牛肉']), // clears 3
        _recipe('two', '青椒牛肉', ['青椒', '牛肉']), // clears 2
      ];
      final ranked = recipesRankedByExpiringUse(recommended, expiring);
      expect(ranked.map((r) => r.id), ['three', 'two', 'one']);
    });

    test('keeps recommended order on ties and drops non-expiring recipes', () {
      final expiring = {'番茄'};
      final recommended = [
        _recipe('keep1', '番茄汤', ['番茄', '盐']), // clears 1
        _recipe('drop', '白米饭', ['米']), // clears 0 -> dropped
        _recipe('keep2', '番茄炒蛋', ['番茄', '蛋']), // clears 1, ties after keep1
      ];
      final ranked = recipesRankedByExpiringUse(recommended, expiring);
      expect(ranked.map((r) => r.id), ['keep1', 'keep2']);
    });

    test('returns empty when nothing is expiring', () {
      final recommended = [
        _recipe('a', '番茄炒蛋', ['番茄']),
      ];
      expect(recipesRankedByExpiringUse(recommended, <String>{}), isEmpty);
    });
  });

  group('expiringIngredientCountForNames', () {
    test('counts distinct expiring names via substring match', () {
      final expiring = {'小番茄', '牛肉'};
      // '番茄' ⊂ '小番茄' and '牛肉' == '牛肉' -> 2 distinct expiring names cleared.
      final recipe = _recipe('r', '番茄牛肉', ['番茄', '牛肉', '蛋']);
      expect(expiringIngredientCountForNames(expiring, recipe), 2);
    });

    test('is zero when the recipe shares no expiring item', () {
      final recipe = _recipe('r', '白饭', ['米']);
      expect(expiringIngredientCountForNames({'番茄'}, recipe), 0);
    });
  });
}
