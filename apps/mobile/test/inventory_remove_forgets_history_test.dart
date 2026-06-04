import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

/// add_history 是本地补货频次记忆(Drift 表)。这些用例锁定一条产品不变量:
/// **手动删除**食材("不要了")应清掉它的补货历史,而**消费扣减**("吃完了")
/// 必须保留历史——吃完正是「库存不足」卡片该提醒补货的信号。
Future<ProviderContainer> _container({
  required Map<String, dynamic> history,
  required List<Ingredient> inventory,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  final repo = InventoryRepo(db);
  repo.hydrate(inventory);
  await repo.saveHistory(history);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appDatabaseProvider.overrideWithValue(db),
    inventoryRepoProvider.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  return c;
}

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

Map<String, dynamic> _entry(int count, {String unit = '个'}) => {
      'count': count,
      'category': FoodCategories.other,
      'storage': 'fridge',
      'unit': unit,
    };

void main() {
  test('remove forgets the restock history once no same-named row remains',
      () async {
    final c = await _container(
      history: {'西瓜': _entry(3)},
      inventory: [_ing('西瓜')],
    );
    final n = c.read(inventoryProvider.notifier);

    await n.remove(0);

    expect(c.read(inventoryProvider), isEmpty);
    expect(c.read(lowStockItemsProvider), isEmpty,
        reason: '手动删除最后一个西瓜后,不应再提醒补货');
  });

  test('removeMany forgets the restock history of every vanished name',
      () async {
    final c = await _container(
      history: {'西瓜': _entry(3), '芒果': _entry(4)},
      inventory: [_ing('西瓜'), _ing('芒果'), _ing('牛奶')],
    );
    final n = c.read(inventoryProvider.notifier);
    final seeded = c.read(inventoryProvider);

    await n.removeMany([seeded[0], seeded[1]]);

    expect(c.read(inventoryProvider).map((e) => e.name), ['牛奶']);
    expect(c.read(lowStockItemsProvider), isEmpty,
        reason: '批量删除的西瓜/芒果历史都应清除');
  });

  test('remove keeps the history while a same-named row still remains',
      () async {
    final c = await _container(
      history: {'西瓜': _entry(3)},
      inventory: [_ing('西瓜'), _ing('西瓜')],
    );
    final n = c.read(inventoryProvider.notifier);

    await n.remove(0);

    expect(c.read(inventoryProvider), hasLength(1));
    final freq = c.read(frequentItemsProvider);
    expect(freq.map((f) => f.name), contains('西瓜'),
        reason: '库存里还有一个西瓜,补货历史不该清');
    expect(freq.firstWhere((f) => f.name == '西瓜').count, 3);
  });

  test('clearAll forgets the restock history of every cleared item', () async {
    final c = await _container(
      history: {'西瓜': _entry(3), '牛奶': _entry(3)},
      inventory: [_ing('西瓜'), _ing('牛奶')],
    );
    final n = c.read(inventoryProvider.notifier);

    await n.clearAll();

    expect(c.read(inventoryProvider), isEmpty);
    expect(c.read(lowStockItemsProvider), isEmpty);
  });

  test('consuming an item to zero (deduction) keeps its restock history',
      () async {
    final c = await _container(
      history: {'西瓜': _entry(3)},
      inventory: [_ing('西瓜')],
    );
    final n = c.read(inventoryProvider.notifier);
    final proposal = DeductionProposal(
      id: 'p1',
      recipeIngredientName: '西瓜',
      requiredQty: '1',
      candidates: const [
        DeductionCandidate(
          inventoryRowIndex: 0,
          displayLabel: '西瓜',
          inventoryRowName: '西瓜',
          inventoryRowUnit: '个',
        ),
      ],
      chosenIndex: 0,
      deductAmount: '1',
      selected: true,
    );

    await n.applyDeductionProposals([proposal]);

    expect(c.read(inventoryProvider), isEmpty);
    expect(c.read(lowStockItemsProvider).map((f) => f.name), contains('西瓜'),
        reason: '吃完才是该提醒补货的时刻,历史必须保留');
  });
}
