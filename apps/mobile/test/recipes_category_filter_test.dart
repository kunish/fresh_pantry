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

LocalRecipeRepository _threeRecipes() => LocalRecipeRepository(
  loadString: (_) async => jsonEncode([
    Recipe(
      id: 'r1',
      name: '可乐鸡翅',
      category: '荤菜',
      difficulty: 3,
      cookingMinutes: 40,
      description: '',
      ingredients: [RecipeIngredient(name: '鸡翅中')],
      steps: const ['做'],
    ).toJson(),
    Recipe(
      id: 'r2',
      name: '红烧肉',
      category: '荤菜',
      difficulty: 3,
      cookingMinutes: 60,
      description: '',
      ingredients: [RecipeIngredient(name: '五花肉')],
      steps: const ['做'],
    ).toJson(),
    Recipe(
      id: 'r3',
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
  testWidgets('category chips filter recipes; 全部 restores the full list', (
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
            localRecipeRepository: _threeRecipes(),
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

    // All three visible, and both category chips rendered (荤菜 leads: count 2).
    expect(find.text('可乐鸡翅'), findsOneWidget);
    expect(find.text('红烧肉'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.byKey(const Key('recipe_category_荤菜')), findsOneWidget);
    expect(find.byKey(const Key('recipe_category_素菜')), findsOneWidget);

    // Filter to 素菜: only 番茄炒蛋 remains.
    await tester.tap(find.byKey(const Key('recipe_category_素菜')));
    await tester.pumpAndSettle();
    expect(find.text('可乐鸡翅'), findsNothing);
    expect(find.text('红烧肉'), findsNothing);
    expect(find.text('番茄炒蛋'), findsOneWidget);

    // Switch to 荤菜: the two meat dishes show, the veg dish hides.
    await tester.tap(find.byKey(const Key('recipe_category_荤菜')));
    await tester.pumpAndSettle();
    expect(find.text('可乐鸡翅'), findsOneWidget);
    expect(find.text('红烧肉'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsNothing);

    // Tapping the active 荤菜 chip again clears back to 全部.
    await tester.tap(find.byKey(const Key('recipe_category_荤菜')));
    await tester.pumpAndSettle();
    expect(find.text('番茄炒蛋'), findsOneWidget);

    // The 全部 chip also restores everything after a category is picked.
    await tester.tap(find.byKey(const Key('recipe_category_素菜')));
    await tester.pumpAndSettle();
    expect(find.text('可乐鸡翅'), findsNothing);
    await tester.tap(find.byKey(const Key('recipe_category_全部')));
    await tester.pumpAndSettle();
    expect(find.text('可乐鸡翅'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
  });

  testWidgets('category + time filter empty shows a category-specific message', (
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
            localRecipeRepository: _threeRecipes(),
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

    // 荤菜 dishes are 40/60 min; narrowing to ≤15 min empties the category.
    await tester.tap(find.byKey(const Key('recipe_category_荤菜')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('⏱ 15 分钟内'));
    await tester.pumpAndSettle();

    expect(find.text('该分类下暂无符合条件的菜谱，换个分类试试'), findsOneWidget);
  });
}
