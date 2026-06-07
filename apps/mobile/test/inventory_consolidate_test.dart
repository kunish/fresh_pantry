import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Future<ProviderContainer> _container({
  List<Ingredient> seed = const [],
  AppDatabase? database,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      ...testStorageOverrides(database: database ?? newTestDatabase()),
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(seed),
    ],
  );
}

Ingredient _item({
  String id = '',
  String name = '白糖',
  String quantity = '1',
  String unit = '个',
  String category = FoodCategories.other,
  IconType storage = IconType.pantry,
}) => Ingredient(
  id: id,
  name: name,
  quantity: quantity,
  unit: unit,
  imageUrl: '',
  freshnessPercent: 1,
  state: FreshnessState.fresh,
  category: category,
  storage: storage,
);

void main() {
  test('build auto-merges seeded same-identity non-perishable dups', () async {
    final c = await _container(
      seed: [
        _item(name: '白糖', quantity: '1'),
        _item(name: '盐', quantity: '1'),
        _item(name: '白糖', quantity: '1'),
      ],
    );
    addTearDown(c.dispose);

    final state = c.read(inventoryProvider);

    expect(state.map((e) => e.name), ['白糖', '盐']);
    expect(state.first.quantity, '2', reason: '白糖 1 + 1 = 2');
  });

  test('build leaves a clean list untouched (no merge)', () async {
    final c = await _container(seed: [_item(name: '白糖'), _item(name: '盐')]);
    addTearDown(c.dispose);

    expect(c.read(inventoryProvider).map((e) => e.name), ['白糖', '盐']);
  });

  test('build keeps perishable batches separate', () async {
    final c = await _container(
      seed: [
        _item(name: '牛奶', category: FoodCategories.dairyAndEggs),
        _item(name: '牛奶', category: FoodCategories.dairyAndEggs),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(inventoryProvider).length, 2);
  });

  test('build does not merge across storage areas', () async {
    final c = await _container(
      seed: [
        _item(name: '白糖', storage: IconType.pantry),
        _item(name: '白糖', storage: IconType.fridge),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(inventoryProvider).length, 2);
  });

  test(
    'replaceFromRemote merges household dups arriving via sync inflow',
    () async {
      final c = await _container();
      addTearDown(c.dispose);

      await c.read(inventoryProvider.notifier).replaceFromRemote([
        _item(id: 'a', name: '白糖', quantity: '1'),
        _item(id: 'b', name: '盐', quantity: '1'),
        _item(id: 'c', name: '白糖', quantity: '1'),
      ]);

      final state = c.read(inventoryProvider);
      expect(state.map((e) => e.name), ['白糖', '盐']);
      expect(state.first.quantity, '2');
    },
  );

  test('the consolidation is persisted, so a reload stays merged', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = await _container(
      database: db,
      seed: [_item(name: '白糖', quantity: '1'), _item(name: '白糖', quantity: '1')],
    );
    addTearDown(c.dispose);

    // Trigger build() (which schedules the async persist), then let the
    // microtask + persistence queue drain.
    expect(c.read(inventoryProvider).length, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final saved = await c.read(inventoryRepoProvider).loadAllFor('');
    expect(saved.length, 1, reason: 'the dropped duplicate must be gone on disk');
    expect(saved.single.quantity, '2');
  });
}
