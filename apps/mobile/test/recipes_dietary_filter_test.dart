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

LocalRecipeRepository _twoRecipes() => LocalRecipeRepository(
  loadString: (_) async => jsonEncode([
    Recipe(
      id: 'howtocook:meat_dish/可乐鸡翅',
      name: '可乐鸡翅',
      category: '荤菜',
      difficulty: 3,
      cookingMinutes: 40,
      description: '',
      ingredients: [RecipeIngredient(name: '鸡翅中')],
      steps: const ['做'],
    ).toJson(),
    Recipe(
      id: 'howtocook:vegetable_dish/番茄炒蛋',
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
  testWidgets('adding a 忌口 keyword hides recipes that contain it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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

    // Open the dietary editor, add "鸡翅", then close it.
    await tester.tap(find.byKey(const Key('recipe_dietary_action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '鸡翅');
    await tester.tap(find.byKey(const Key('dietary_add_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dietary_done_button')));
    await tester.pumpAndSettle();

    // 可乐鸡翅 contains 鸡翅中 → filtered out; 番茄炒蛋 stays.
    expect(find.text('可乐鸡翅'), findsNothing);
    expect(find.text('番茄炒蛋'), findsOneWidget);
  });
}
