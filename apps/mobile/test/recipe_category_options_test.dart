import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';

Recipe _recipe(String name, String category) => Recipe(
  id: name,
  name: name,
  category: category,
  difficulty: 1,
  cookingMinutes: 10,
  description: '',
  ingredients: const [],
  steps: const [],
);

void main() {
  group('recipeCategoryOptions', () {
    test('orders distinct categories by recipe count, largest bucket first', () {
      final recipes = [
        _recipe('a', '素菜'),
        _recipe('b', '荤菜'),
        _recipe('c', '荤菜'),
        _recipe('d', '荤菜'),
        _recipe('e', '素菜'),
        _recipe('f', '汤羹'),
      ];
      // 荤菜=3, 素菜=2, 汤羹=1
      expect(recipeCategoryOptions(recipes), ['荤菜', '素菜', '汤羹']);
    });

    test('breaks count ties by first appearance', () {
      final recipes = [
        _recipe('a', '素菜'),
        _recipe('b', '荤菜'),
        _recipe('c', '汤羹'),
      ];
      // all count 1 → order follows first appearance
      expect(recipeCategoryOptions(recipes), ['素菜', '荤菜', '汤羹']);
    });

    test('ignores blank / whitespace-only categories', () {
      final recipes = [
        _recipe('a', ''),
        _recipe('b', '   '),
        _recipe('c', '荤菜'),
      ];
      expect(recipeCategoryOptions(recipes), ['荤菜']);
    });

    test('trims categories and treats trimmed duplicates as one bucket', () {
      final recipes = [
        _recipe('a', '荤菜'),
        _recipe('b', ' 荤菜 '),
      ];
      expect(recipeCategoryOptions(recipes), ['荤菜']);
    });

    test('returns empty for no recipes', () {
      expect(recipeCategoryOptions(const []), isEmpty);
    });
  });
}
