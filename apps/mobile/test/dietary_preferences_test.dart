import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/storage/dietary_preferences_repo.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';

Recipe _recipe(String name, List<String> ingredientNames) => Recipe(
  id: name,
  name: name,
  category: '中餐',
  difficulty: 1,
  cookingMinutes: 10,
  description: '',
  ingredients: [for (final n in ingredientNames) RecipeIngredient(name: n)],
  steps: const [],
);

void main() {
  group('DietaryPreferencesRepo', () {
    test('load returns {} when the key is missing', () {
      expect(DietaryPreferencesRepo(InMemoryStorageAdapter()).load(), isEmpty);
    });

    test('save then load round-trips the keyword set', () {
      final adapter = InMemoryStorageAdapter();
      final repo = DietaryPreferencesRepo(adapter);
      repo.save({'香菜', '花生'});
      expect(repo.load(), {'香菜', '花生'});
    });

    test('save survives a fresh repo over the same adapter', () {
      final adapter = InMemoryStorageAdapter();
      DietaryPreferencesRepo(adapter).save({'香菜'});
      expect(DietaryPreferencesRepo(adapter).load(), {'香菜'});
    });

    test('malformed blob yields {} instead of throwing', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(DietaryPreferencesRepo.storageKey, 'not-json{[');
      expect(DietaryPreferencesRepo(adapter).load(), isEmpty);
    });

    test('skips non-string and empty entries', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        DietaryPreferencesRepo.storageKey,
        json.encode(['香菜', 7, '', null, '花生']),
      );
      expect(DietaryPreferencesRepo(adapter).load(), {'香菜', '花生'});
    });
  });

  group('recipeHasExcludedIngredient', () {
    test('returns false when there are no exclusions', () {
      final recipe = _recipe('番茄炒蛋', ['番茄', '鸡蛋']);
      expect(recipeHasExcludedIngredient(recipe, const {}), isFalse);
    });

    test('matches an ingredient by substring (花生 hides 花生油)', () {
      final recipe = _recipe('宫保鸡丁', ['鸡肉', '花生油', '干辣椒']);
      expect(recipeHasExcludedIngredient(recipe, {'花生'}), isTrue);
    });

    test('is case-insensitive and trims the ingredient name', () {
      final recipe = _recipe('沙拉', [' Coriander ']);
      expect(recipeHasExcludedIngredient(recipe, {'coriander'}), isTrue);
    });

    test('returns false when no ingredient contains any keyword', () {
      final recipe = _recipe('清炒时蔬', ['西兰花', '胡萝卜']);
      expect(recipeHasExcludedIngredient(recipe, {'香菜', '花生'}), isFalse);
    });

    test('ignores empty keywords so they never match everything', () {
      final recipe = _recipe('白米饭', ['大米']);
      expect(recipeHasExcludedIngredient(recipe, {''}), isFalse);
    });
  });
}
