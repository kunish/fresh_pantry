import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...testStorageOverrides(database: db),
    ],
  );
}

void main() {
  test('reload re-reads persisted items instead of emptying them '
      '(pull-to-refresh regression)', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final notifier = container.read(shoppingProvider.notifier);
    // Persist rows the way startup/sync does, so disk and state agree.
    await notifier.replaceFromRemote(const [
      ShoppingItem(
        id: 'milk',
        name: '牛奶',
        detail: '',
        category: FoodCategories.dairyAndEggs,
      ),
      ShoppingItem(
        id: 'tomato',
        name: '番茄',
        detail: '',
        category: FoodCategories.freshProduce,
      ),
    ]);
    expect(container.read(shoppingProvider), hasLength(2));

    // The old pull-to-refresh ref.invalidate'd shoppingProvider, but build()
    // returns a one-shot startup seed that's already consumed → it fell back
    // to an empty list. reload() must re-read the persisted rows.
    await notifier.reload();

    expect(container.read(shoppingProvider).map((i) => i.name).toSet(), {
      '牛奶',
      '番茄',
    });
  });

  test('add trims item name and detail before saving state', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final added = await container
        .read(shoppingProvider.notifier)
        .add(
          const ShoppingItem(
            id: 'milk',
            name: '  牛奶  ',
            detail: '  1 盒  ',
            category: FoodCategories.dairyAndEggs,
          ),
        );

    expect(added, isTrue);
    final item = container.read(shoppingProvider).single;
    expect(item.name, '牛奶');
    expect(item.detail, '1 盒');
  });

  test(
    'replaceFromRemote normalizes (dedup + unique ids) so in-memory matches a reload',
    () async {
      final container = await _container();
      addTearDown(container.dispose);

      await container.read(shoppingProvider.notifier).replaceFromRemote(const [
        ShoppingItem(
          id: 'dup',
          name: '牛奶',
          detail: '',
          category: FoodCategories.dairyAndEggs,
        ),
        ShoppingItem(
          id: 'dup',
          name: '面包',
          detail: '',
          category: FoodCategories.freshProduce,
        ),
      ]);

      final ids = container.read(shoppingProvider).map((e) => e.id).toSet();
      // Duplicate id was reassigned, not silently merged/dropped.
      expect(container.read(shoppingProvider), hasLength(2));
      expect(ids, hasLength(2));
    },
  );
}
