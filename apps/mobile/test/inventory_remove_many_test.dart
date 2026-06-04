import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Ingredient _ing(String name) => Ingredient(
  name: name,
  quantity: '1',
  unit: '份',
  imageUrl: '',
  freshnessPercent: 1,
  state: FreshnessState.fresh,
  category: FoodCategories.freshProduce,
  storage: IconType.fridge,
);

Future<ProviderContainer> _container(List<Ingredient> seed) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue(seed),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('removeMany deletes every targeted row, keeping the rest', () async {
    final c = await _container([_ing('番茄'), _ing('牛奶'), _ing('米饭')]);
    final n = c.read(inventoryProvider.notifier);
    final seeded = c.read(inventoryProvider);

    await n.removeMany([seeded[0], seeded[2]]);

    expect(c.read(inventoryProvider).map((e) => e.name), ['牛奶']);
  });

  test('removeMany returns removed items with their original indices ascending',
      () async {
    final c = await _container([_ing('番茄'), _ing('牛奶'), _ing('米饭')]);
    final n = c.read(inventoryProvider.notifier);
    final seeded = c.read(inventoryProvider);

    // Pass targets out of order; the result must still be ascending by index.
    final removed = await n.removeMany([seeded[2], seeded[0]]);

    expect(removed.map((r) => r.index), [0, 2]);
    expect(removed.map((r) => r.item.name), ['番茄', '米饭']);
  });

  test('removeMany is a no-op for an empty selection', () async {
    final c = await _container([_ing('番茄')]);
    final n = c.read(inventoryProvider.notifier);

    final removed = await n.removeMany(const []);

    expect(removed, isEmpty);
    expect(c.read(inventoryProvider), hasLength(1));
  });

  test('removeMany ignores items that are no longer in the inventory', () async {
    final c = await _container([_ing('番茄'), _ing('牛奶')]);
    final n = c.read(inventoryProvider.notifier);
    final seeded = c.read(inventoryProvider);

    final removed = await n.removeMany([seeded[0], _ing('幽灵食材')]);

    expect(removed.map((r) => r.item.name), ['番茄']);
    expect(c.read(inventoryProvider).map((e) => e.name), ['牛奶']);
  });

  test('removeMany then insertAt (ascending) restores the original order',
      () async {
    final c = await _container([_ing('番茄'), _ing('牛奶'), _ing('米饭')]);
    final n = c.read(inventoryProvider.notifier);
    final seeded = c.read(inventoryProvider);

    final removed = await n.removeMany([seeded[0], seeded[2]]);
    for (final r in removed) {
      await n.insertAt(r.index, r.item);
    }

    expect(c.read(inventoryProvider).map((e) => e.name), ['番茄', '牛奶', '米饭']);
  });
}
