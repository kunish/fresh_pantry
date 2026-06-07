import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/meal_plan_entry.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/meal_plan_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('加入计划: tap calendar -> pick a day -> entry is planned', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final recipe = Recipe(
      id: 'r1',
      name: '番茄炒蛋',
      category: '家常菜',
      difficulty: 1,
      cookingMinutes: 15,
      description: '',
      ingredients: const [],
      steps: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: const []),
        ],
        child: MaterialApp(home: RecipeDetailScreen(recipe: recipe)),
      ),
    );
    await tester.pumpAndSettle();

    // Open the day picker from the hero chrome.
    await tester.tap(find.byKey(const Key('recipe_add_to_plan_action')));
    await tester.pumpAndSettle();
    expect(find.text('加入哪天的计划?'), findsOneWidget);

    // Pick today.
    final today = MealPlanEntry.dateOnly(DateTime.now());
    await tester.tap(
      find.byKey(ValueKey('plan-day-${MealPlanEntry.dateKey(today)}')),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecipeDetailScreen)),
    );
    final entries = container.read(mealPlanProvider);
    expect(entries, hasLength(1));
    expect(entries.single.recipeId, 'r1');
    expect(entries.single.recipeName, '番茄炒蛋');
    expect(entries.single.date, today);

    // Confirmation surfaces with a shortcut to the plan.
    expect(find.text('查看'), findsOneWidget);
  });
}
