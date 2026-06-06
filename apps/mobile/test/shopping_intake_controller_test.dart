import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/shopping_intake_controller.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/intake_proposal_factory.dart';
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

ShoppingItem _item(String id, String name) => ShoppingItem(
      id: id,
      name: name,
      detail: '1 个',
      category: FoodCategories.freshProduce,
      isChecked: true,
    );

void main() {
  test('buildProposals mints ix_ proposal ids for each item', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(shoppingIntakeControllerProvider);
    final proposals = controller.buildProposals([_item('a', '番茄')]);

    expect(proposals.single.id, IntakeProposalFactory.proposalIdForShoppingItem('a'));
    expect(proposals.single.id, 'ix_a');
  });

  test('removeApplied clears only the rows whose proposal applied', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final notifier = container.read(shoppingProvider.notifier);
    final source = [_item('a', '番茄'), _item('b', '黄瓜'), _item('c', '土豆')];
    await notifier.replaceFromRemote(source);
    expect(container.read(shoppingProvider), hasLength(3));

    final controller = container.read(shoppingIntakeControllerProvider);
    // Only a and c applied; b was deselected/cancelled in Review.
    await controller.removeApplied(source, {
      IntakeProposalFactory.proposalIdForShoppingItem('a'),
      IntakeProposalFactory.proposalIdForShoppingItem('c'),
    });

    expect(
      container.read(shoppingProvider).map((i) => i.id).toList(),
      ['b'],
    );
  });

  test('removeApplied with an empty applied set is a no-op', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final notifier = container.read(shoppingProvider.notifier);
    final source = [_item('a', '番茄')];
    await notifier.replaceFromRemote(source);

    final controller = container.read(shoppingIntakeControllerProvider);
    await controller.removeApplied(source, <String>{});

    expect(container.read(shoppingProvider), hasLength(1));
  });
}
