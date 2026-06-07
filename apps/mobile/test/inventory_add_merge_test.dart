import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Future<ProviderContainer> _container({List<Ingredient> seed = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      ...testStorageOverrides(database: newTestDatabase()),
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(seed),
    ],
  );
}

Ingredient _item({
  String name = '白糖',
  String quantity = '1',
  String unit = '个',
  String category = FoodCategories.other,
  IconType storage = IconType.pantry,
}) => Ingredient(
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
  test(
    'add merges a non-perishable into the existing same-identity row',
    () async {
      final c = await _container(seed: [_item(quantity: '1')]);
      final notifier = c.read(inventoryProvider.notifier);

      await notifier.add(_item(quantity: '1'));

      final state = c.read(inventoryProvider);
      expect(state.length, 1, reason: 'identical 白糖 must not create a 2nd row');
      expect(state.single.quantity, '2', reason: '1 + 1 = 2');
    },
  );

  test('add returns the merged row (not the trailing row)', () async {
    final c = await _container(
      seed: [_item(name: '白糖', quantity: '1'), _item(name: '盐', quantity: '1')],
    );
    final notifier = c.read(inventoryProvider.notifier);

    final result = await notifier.add(_item(name: '白糖', quantity: '1'));

    expect(result.name, '白糖');
    expect(result.quantity, '2');
  });

  test(
    'add creates a new row when storage differs (different identity)',
    () async {
      final c = await _container(seed: [_item(storage: IconType.pantry)]);
      final notifier = c.read(inventoryProvider.notifier);

      await notifier.add(_item(storage: IconType.fridge));

      expect(c.read(inventoryProvider).length, 2);
    },
  );

  test('add keeps perishable batches separate (ADR-0001)', () async {
    final c = await _container(
      seed: [_item(name: '牛奶', category: FoodCategories.dairyAndEggs)],
    );
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.add(_item(name: '牛奶', category: FoodCategories.dairyAndEggs));

    expect(
      c.read(inventoryProvider).length,
      2,
      reason: 'perishables always create a new batch',
    );
  });
}
