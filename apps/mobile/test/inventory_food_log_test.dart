import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/food_log_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Ingredient _ing(
  String name, {
  String qty = '1',
  FreshnessState state = FreshnessState.fresh,
  String category = FoodCategories.freshProduce,
}) => Ingredient(
  name: name,
  quantity: qty,
  unit: '个',
  imageUrl: '',
  freshnessPercent: 1,
  state: state,
  category: category,
  storage: IconType.fridge,
);

Future<ProviderContainer> _container(List<Ingredient> seed) async {
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

void main() {
  test('remove with outcome logs a wasted departure; wasExpiring from state', () async {
    final c = await _container([
      _ing('烂菜', state: FreshnessState.expired),
    ]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.remove(0, outcome: FoodLogOutcome.wasted);

    final log = c.read(foodLogProvider);
    expect(log, hasLength(1));
    expect(log.single.name, '烂菜');
    expect(log.single.outcome, FoodLogOutcome.wasted);
    expect(log.single.wasExpiring, isTrue); // expired at departure
    expect(log.single.category, FoodCategories.freshProduce);
  });

  test('remove returns the logId; undoRecord reverses the phantom log', () async {
    final c = await _container([_ing('番茄')]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    final logId = await notifier.remove(0, outcome: FoodLogOutcome.wasted);
    expect(logId, isNotNull);
    expect(c.read(foodLogProvider), hasLength(1));

    // Simulate an undo: re-insert + reverse the log entry.
    await notifier.insertAt(0, _ing('番茄'));
    await c.read(foodLogProvider.notifier).undoRecord(logId!);
    expect(c.read(foodLogProvider), isEmpty);
  });

  test('removeMany returns a logId per removed item', () async {
    final a = _ing('A');
    final b = _ing('B');
    final c = await _container([a, b]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    final removed = await notifier.removeMany(
      [a, b],
      outcome: FoodLogOutcome.wasted,
    );
    expect(removed.every((r) => r.logId != null), isTrue);
    expect(removed.map((r) => r.logId).toSet(), hasLength(2)); // distinct ids
  });

  test('remove without an outcome logs nothing', () async {
    final c = await _container([_ing('番茄')]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.remove(0);

    expect(c.read(foodLogProvider), isEmpty);
  });

  test('removeMany with outcome logs each removed item', () async {
    final a = _ing('A');
    final b = _ing('B');
    final c = await _container([a, b]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.removeMany([a, b], outcome: FoodLogOutcome.consumed);

    final log = c.read(foodLogProvider);
    expect(log, hasLength(2));
    expect(log.map((e) => e.name).toSet(), {'A', 'B'});
    expect(log.every((e) => e.outcome == FoodLogOutcome.consumed), isTrue);
  });

  test('deduction that empties a row logs a consumed departure', () async {
    final c = await _container([
      _ing('蒜', qty: '1', state: FreshnessState.urgent),
    ]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '蒜',
        requiredQty: '1瓣',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '蒜 1 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
        action: DeductionAction.deduct,
      ),
    ]);

    expect(c.read(inventoryProvider), isEmpty);
    final log = c.read(foodLogProvider);
    expect(log, hasLength(1));
    expect(log.single.outcome, FoodLogOutcome.consumed);
    expect(log.single.rescuedExpiring, isTrue); // urgent item cooked = rescued
  });

  test('partial deduction (row remains) logs nothing', () async {
    final c = await _container([_ing('葱', qty: '3')]);
    addTearDown(c.dispose);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 3 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
        action: DeductionAction.deduct,
      ),
    ]);

    expect(c.read(inventoryProvider).single.quantity, '2');
    expect(c.read(foodLogProvider), isEmpty);
  });
}
