import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';

void main() {
  group('dedupeRecipeIngredients', () {
    test('collapses two identical names, keeping the first occurrence', () {
      final result = dedupeRecipeIngredients([
        RecipeIngredient(name: '味精', quantity: '1', unit: '勺'),
        RecipeIngredient(name: '盐', quantity: '2', unit: '克'),
        RecipeIngredient(name: '味精', quantity: '99', unit: '袋'),
      ]);

      expect(result.map((i) => i.name), ['味精', '盐']);
      // First occurrence's amount survives, the later duplicate is dropped.
      expect(result.first.quantity, '1');
      expect(result.first.unit, '勺');
    });

    test('dedupes case-insensitively and after trimming whitespace', () {
      final result = dedupeRecipeIngredients([
        RecipeIngredient(name: '味精'),
        RecipeIngredient(name: ' 味精 '),
        RecipeIngredient(name: 'MSG'),
        RecipeIngredient(name: 'msg'),
      ]);

      expect(result.map((i) => i.name), ['味精', 'MSG']);
    });

    test('preserves order and keeps distinct ingredients untouched', () {
      final result = dedupeRecipeIngredients([
        RecipeIngredient(name: '味精'),
        RecipeIngredient(name: '鸡精'),
        RecipeIngredient(name: '盐'),
      ]);

      expect(result.map((i) => i.name), ['味精', '鸡精', '盐']);
    });
  });

  group('Recipe.fromJson', () {
    test('dedupes duplicate ingredient names on load', () {
      final recipe = Recipe.fromJson({
        'id': 'r1',
        'name': '番茄炒蛋',
        'ingredients': [
          {'name': '味精', 'quantity': '1', 'unit': '勺'},
          {'name': '番茄', 'quantity': '2', 'unit': '个'},
          {'name': '味精', 'quantity': '5', 'unit': '袋'},
        ],
      });

      expect(recipe.ingredients.map((i) => i.name), ['味精', '番茄']);
    });
  });
}
