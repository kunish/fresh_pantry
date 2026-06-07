import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/meal_plan_provider.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart' show AppDatabase;
import 'package:fresh_pantry/sync/sync_ids.dart';

import 'support/test_database.dart';

Recipe _recipe(String id, String name, {List<String> ingredients = const []}) =>
    Recipe(
      id: id,
      name: name,
      category: '家常菜',
      difficulty: 1,
      cookingMinutes: 15,
      description: '',
      ingredients: ingredients.map((n) => RecipeIngredient(name: n)).toList(),
      steps: const [],
      imageUrl: 'https://example.com/$id.jpg',
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

ProviderContainer _container(AppDatabase db) =>
    ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

void main() {
  test('addEntry persists to Drift and survives reload', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);
    final notifier = c.read(mealPlanProvider.notifier);

    final id = await notifier.addEntry(
      date: DateTime(2026, 6, 8, 19),
      recipe: _recipe('r1', '番茄炒蛋'),
    );

    expect(isUuid(id), isTrue);
    final entry = c.read(mealPlanProvider).single;
    expect(entry.recipeName, '番茄炒蛋');
    expect(entry.date, DateTime(2026, 6, 8)); // time-of-day truncated
    expect(entry.recipeImageUrl, 'https://example.com/r1.jpg');

    // reload reads from Drift, not memory -> proves the write hit disk.
    await notifier.reload();
    expect(c.read(mealPlanProvider).single.id, id);
  });

  test('remove drops the entry from state and disk', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);
    final notifier = c.read(mealPlanProvider.notifier);

    final id = await notifier.addEntry(
      date: DateTime(2026, 6, 8),
      recipe: _recipe('r1', 'Soup'),
    );
    await notifier.remove(id);

    expect(c.read(mealPlanProvider), isEmpty);
    await notifier.reload();
    expect(c.read(mealPlanProvider), isEmpty);
  });

  test('setDone toggles the done flag and persists', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);
    final notifier = c.read(mealPlanProvider.notifier);

    final id = await notifier.addEntry(
      date: DateTime(2026, 6, 8),
      recipe: _recipe('r1', 'Soup'),
    );
    await notifier.setDone(id, true);

    expect(c.read(mealPlanProvider).single.done, isTrue);
    await notifier.reload();
    expect(c.read(mealPlanProvider).single.done, isTrue);
  });

  test('moveToDate reschedules the entry (date-only) and persists', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);
    final notifier = c.read(mealPlanProvider.notifier);

    final id = await notifier.addEntry(
      date: DateTime(2026, 6, 8),
      recipe: _recipe('r1', 'Soup'),
    );
    await notifier.moveToDate(id, DateTime(2026, 6, 11, 8, 30));

    expect(c.read(mealPlanProvider).single.date, DateTime(2026, 6, 11));
    await notifier.reload();
    expect(c.read(mealPlanProvider).single.date, DateTime(2026, 6, 11));
  });

  test('addEntry floors servings to at least 1', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);
    final notifier = c.read(mealPlanProvider.notifier);

    await notifier.addEntry(
      date: DateTime(2026, 6, 8),
      recipe: _recipe('r1', 'Soup'),
      servings: 0,
    );
    expect(c.read(mealPlanProvider).single.servings, 1);
  });

  test('mutations on a missing id are no-ops', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);
    final notifier = c.read(mealPlanProvider.notifier);

    await notifier.setDone('does-not-exist', true);
    await notifier.remove('');
    expect(c.read(mealPlanProvider), isEmpty);
  });

  group('derived providers', () {
    ProviderContainer derivedContainer(
      AppDatabase db, {
      List<Recipe> presets = const [],
      List<Ingredient> inventory = const [],
    }) {
      return ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          recipesProvider.overrideWith((ref) async => presets),
          if (inventory.isNotEmpty)
            inventorySeedProvider.overrideWithValue(inventory),
        ],
      );
    }

    test('mealPlanByDayProvider groups entries by date', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = derivedContainer(db);
      addTearDown(c.dispose);
      final n = c.read(mealPlanProvider.notifier);
      await n.addEntry(date: DateTime(2026, 6, 8), recipe: _recipe('r1', 'A'));
      await n.addEntry(
        date: DateTime(2026, 6, 8, 20),
        recipe: _recipe('r2', 'B'),
      );
      await n.addEntry(date: DateTime(2026, 6, 9), recipe: _recipe('r3', 'C'));

      final byDay = c.read(mealPlanByDayProvider);
      expect(byDay[DateTime(2026, 6, 8)], hasLength(2));
      expect(byDay[DateTime(2026, 6, 9)], hasLength(1));
    });

    test(
      'missing = planned needs minus inventory, deduped, excluding done',
      () async {
        final db = newTestDatabase();
        addTearDown(db.close);
        final tomato = _recipe('r1', '番茄炒蛋', ingredients: ['番茄', '鸡蛋']);
        final soup = _recipe('r2', '蛋汤', ingredients: ['鸡蛋', '葱']);
        final c = derivedContainer(
          db,
          presets: [tomato, soup],
          inventory: [_ing('番茄')],
        );
        addTearDown(c.dispose);
        await c.read(recipesProvider.future); // resolve async preset load

        final n = c.read(mealPlanProvider.notifier);
        await n.addEntry(date: DateTime(2026, 6, 8), recipe: tomato);
        final soupId = await n.addEntry(
          date: DateTime(2026, 6, 8),
          recipe: soup,
        );

        final missing = c.read(mealPlanMissingIngredientsProvider);
        expect(missing, containsAll(['鸡蛋', '葱']));
        expect(missing, isNot(contains('番茄'))); // already in inventory
        expect(missing.where((e) => e == '鸡蛋'), hasLength(1)); // deduped

        await n.setDone(soupId, true); // only soup needed 葱
        expect(c.read(mealPlanMissingIngredientsProvider), ['鸡蛋']);
      },
    );

    test('entry whose recipe is unknown contributes nothing', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = derivedContainer(db); // empty library
      addTearDown(c.dispose);
      await c.read(recipesProvider.future);
      final n = c.read(mealPlanProvider.notifier);
      await n.addEntry(
        date: DateTime(2026, 6, 8),
        recipe: _recipe('ghost', 'X', ingredients: ['幽灵食材']),
      );
      expect(c.read(mealPlanMissingIngredientsProvider), isEmpty);
    });

    test('week summary: zeroed when no entries', () {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = derivedContainer(db);
      addTearDown(c.dispose);
      expect(c.read(mealPlanWeekSummaryProvider), (
        upcoming: 0,
        today: 0,
        missing: 0,
      ));
    });

    test('week summary: counts in-window upcoming, today, and missing', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final tomato = _recipe('r1', '番茄炒蛋', ingredients: ['番茄', '鸡蛋']);
      // Empty inventory -> both ingredients count as missing.
      final c = derivedContainer(db, presets: [tomato]);
      addTearDown(c.dispose);
      await c.read(recipesProvider.future);
      final n = c.read(mealPlanProvider.notifier);

      final today = DateTime.now();
      await n.addEntry(date: today, recipe: tomato);
      await n.addEntry(
        date: today.add(const Duration(days: 2)),
        recipe: _recipe('r2', 'B'),
      );
      // Outside the 7-day window and in the past are both excluded from counts.
      await n.addEntry(
        date: today.add(const Duration(days: 30)),
        recipe: _recipe('r3', 'C'),
      );
      await n.addEntry(
        date: today.subtract(const Duration(days: 1)),
        recipe: _recipe('r4', 'D'),
      );

      final s = c.read(mealPlanWeekSummaryProvider);
      expect(s.upcoming, 2); // today + day+2; excludes +30 and -1
      expect(s.today, 1);
      expect(s.missing, 2); // 番茄 + 鸡蛋 from r1
    });
  });
}
