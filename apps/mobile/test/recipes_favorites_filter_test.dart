import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipes_screen.dart';
import 'package:fresh_pantry/storage/local_recipe_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

const _wingsId = 'howtocook:meat_dish/可乐鸡翅';
const _tomatoId = 'howtocook:vegetable_dish/番茄炒蛋';

LocalRecipeRepository _twoRecipes() => LocalRecipeRepository(
  loadString: (_) async => jsonEncode([
    Recipe(
      id: _wingsId,
      name: '可乐鸡翅',
      category: '荤菜',
      difficulty: 3,
      cookingMinutes: 40,
      description: '',
      ingredients: [RecipeIngredient(name: '鸡翅中')],
      steps: const ['做'],
    ).toJson(),
    Recipe(
      id: _tomatoId,
      name: '番茄炒蛋',
      category: '素菜',
      difficulty: 1,
      cookingMinutes: 15,
      description: '',
      ingredients: [RecipeIngredient(name: '番茄')],
      steps: const ['做'],
    ).toJson(),
  ]),
);

void main() {
  testWidgets('favorites-only toggle shows only favorited recipes', (
    tester,
  ) async {
    // Seed 番茄炒蛋 as a favorite via the prefs-backed favorites store.
    SharedPreferences.setMockInitialValues({
      'favorite_recipe_ids': jsonEncode([_tomatoId]),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: const <Ingredient>[],
            localRecipeRepository: _twoRecipes(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: RecipesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('探索'));
    await tester.pumpAndSettle();

    expect(find.text('可乐鸡翅'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recipe_favorites_only')));
    await tester.pumpAndSettle();

    expect(find.text('可乐鸡翅'), findsNothing);
    expect(find.text('番茄炒蛋'), findsOneWidget);

    // Toggling off restores the full list.
    await tester.tap(find.byKey(const Key('recipe_favorites_only')));
    await tester.pumpAndSettle();
    expect(find.text('可乐鸡翅'), findsOneWidget);
  });
}
