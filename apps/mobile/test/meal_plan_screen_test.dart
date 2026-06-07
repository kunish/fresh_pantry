import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/meal_plan_entry.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/meal_plan_provider.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/meal_plan_screen.dart';

import 'support/test_database.dart';

MealPlanEntry _entry({
  required String id,
  required DateTime date,
  required String recipeId,
  required String name,
  bool done = false,
}) => MealPlanEntry(
  id: id,
  date: date,
  recipeId: recipeId,
  recipeName: name,
  done: done,
);

Recipe _recipe(String id, String name, List<String> ingredients) => Recipe(
  id: id,
  name: name,
  category: '家常菜',
  difficulty: 1,
  cookingMinutes: 15,
  description: '',
  ingredients: ingredients.map((n) => RecipeIngredient(name: n)).toList(),
  steps: const [],
);

Ingredient _ing(String name) => Ingredient(
  name: name,
  quantity: '1',
  unit: '个',
  imageUrl: '',
  freshnessPercent: 1,
  state: FreshnessState.fresh,
  category: FoodCategories.other,
  storage: IconType.fridge,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<MealPlanEntry> entries,
  List<Recipe> presets = const [],
  List<Ingredient> inventory = const [],
}) async {
  final db = newTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mealPlanSeedProvider.overrideWithValue(entries),
        // Override recipesProvider so the screen's missing-ingredient calc never
        // loads the real ~1MB recipe asset (which would stall pumpAndSettle).
        recipesProvider.overrideWith((ref) async => presets),
        if (inventory.isNotEmpty)
          inventorySeedProvider.overrideWithValue(inventory),
      ],
      child: const MaterialApp(home: MealPlanScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));

void main() {
  testWidgets('renders planned entries; empty days show placeholder', (
    tester,
  ) async {
    final today = DateTime.now();
    await _pump(
      tester,
      entries: [
        _entry(id: 'e1', date: today, recipeId: 'r1', name: '番茄炒蛋'),
      ],
    );

    expect(find.text('本周计划'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.text('还没安排'), findsWidgets); // other days in the 7-day window
    // No resolvable recipe -> no missing -> no shopping prompt card.
    expect(find.byKey(const ValueKey('mp-missing')), findsNothing);
  });

  testWidgets('shows empty state when there are no entries', (tester) async {
    await _pump(tester, entries: const []);
    expect(find.text('还没有膳食计划'), findsOneWidget);
  });

  testWidgets('missing-ingredient card adds the shortfall to shopping', (
    tester,
  ) async {
    final today = DateTime.now();
    await _pump(
      tester,
      entries: [
        _entry(id: 'e1', date: today, recipeId: 'r1', name: '番茄炒蛋'),
      ],
      presets: [
        _recipe('r1', '番茄炒蛋', ['番茄', '鸡蛋']),
      ],
      inventory: [_ing('番茄')],
    );

    // 番茄 already stocked -> only 鸡蛋 is missing.
    expect(find.text('本周还缺 1 样食材'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mp-missing')));
    await tester.pumpAndSettle();

    final shopping = _containerOf(tester).read(shoppingProvider);
    expect(shopping.any((i) => i.name == '鸡蛋'), isTrue);
    expect(shopping.any((i) => i.name == '番茄'), isFalse);
  });

  testWidgets('delete removes the entry', (tester) async {
    final today = DateTime.now();
    await _pump(
      tester,
      entries: [
        _entry(id: 'e1', date: today, recipeId: 'r1', name: '番茄炒蛋'),
      ],
    );
    expect(find.text('番茄炒蛋'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mp-del-e1')));
    await tester.pumpAndSettle();

    expect(find.text('番茄炒蛋'), findsNothing);
    expect(_containerOf(tester).read(mealPlanProvider), isEmpty);
  });

  testWidgets('done toggle marks the entry cooked', (tester) async {
    final today = DateTime.now();
    await _pump(
      tester,
      entries: [
        _entry(id: 'e1', date: today, recipeId: 'r1', name: '番茄炒蛋'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('mp-done-e1')));
    await tester.pumpAndSettle();

    expect(_containerOf(tester).read(mealPlanProvider).single.done, isTrue);
  });
}
