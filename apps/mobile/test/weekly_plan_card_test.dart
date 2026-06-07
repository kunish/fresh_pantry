import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/meal_plan_entry.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/meal_plan_screen.dart';
import 'package:fresh_pantry/widgets/dashboard/weekly_plan_card.dart';

import 'support/test_database.dart';

MealPlanEntry _entry({
  required String id,
  required DateTime date,
  required String recipeId,
  required String name,
}) => MealPlanEntry(id: id, date: date, recipeId: recipeId, recipeName: name);

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
        // Override so the missing-ingredient calc never loads the ~1MB recipe
        // asset (which would stall pumpAndSettle).
        recipesProvider.overrideWith((ref) async => presets),
        if (inventory.isNotEmpty)
          inventorySeedProvider.overrideWithValue(inventory),
      ],
      child: const MaterialApp(home: Scaffold(body: WeeklyPlanCard())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty plan shows the planning invite (always visible)', (
    tester,
  ) async {
    await _pump(tester, entries: const []);
    expect(find.text('本周计划'), findsOneWidget);
    expect(find.textContaining('规划这周吃什么'), findsOneWidget);
  });

  testWidgets('shows planned count and missing badge', (tester) async {
    final today = DateTime.now();
    await _pump(
      tester,
      entries: [_entry(id: 'e1', date: today, recipeId: 'r1', name: '番茄炒蛋')],
      presets: [
        _recipe('r1', '番茄炒蛋', ['番茄', '鸡蛋']),
      ],
      inventory: [_ing('番茄')], // 鸡蛋 missing -> 1
    );
    expect(find.text('本周已排 1 顿 · 今天 1 顿'), findsOneWidget);
    expect(find.text('还缺 1 样'), findsOneWidget);
  });

  testWidgets('no missing badge when inventory covers the plan', (
    tester,
  ) async {
    final today = DateTime.now();
    await _pump(
      tester,
      entries: [_entry(id: 'e1', date: today, recipeId: 'r1', name: '番茄炒蛋')],
      presets: [
        _recipe('r1', '番茄炒蛋', ['番茄']),
      ],
      inventory: [_ing('番茄')],
    );
    expect(find.textContaining('还缺'), findsNothing);
  });

  testWidgets('tap opens the meal plan screen', (tester) async {
    await _pump(tester, entries: const []);
    await tester.tap(find.byKey(const ValueKey('dash-weekly-plan')));
    await tester.pumpAndSettle();
    expect(find.byType(MealPlanScreen), findsOneWidget);
  });
}
