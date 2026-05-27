import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/storage/shopping_repo.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

void main() {
  test('shopping toggle enqueues sync operation', () async {
    final adapter = InMemoryStorageAdapter();
    final outbox = SyncOutboxRepo(adapter);
    final shoppingRepo = ShoppingRepo(adapter)
      ..saveItems([
        const ShoppingItem(
          id: 'item_1',
          name: 'Rice',
          detail: '',
          category: '主食',
          remoteVersion: 7,
        ),
      ]);
    final container = _container(
      adapter: adapter,
      outbox: outbox,
      shoppingRepo: shoppingRepo,
    );
    addTearDown(container.dispose);

    await container.read(shoppingProvider.notifier).toggleCheck('item_1');

    final operation = outbox.loadPending().single;
    expect(operation.householdId, 'household_1');
    expect(operation.entityType, SyncEntityType.shoppingItem);
    expect(operation.entityId, 'item_1');
    expect(operation.operation, SyncOperationType.toggleChecked);
    expect(operation.patch, {'isChecked': true});
    expect(operation.baseVersion, 7);
    expect(operation.clientId, 'client_1');
  });

  test('inventory add enqueues create sync operation', () async {
    final adapter = InMemoryStorageAdapter();
    final outbox = SyncOutboxRepo(adapter);
    final container = _container(adapter: adapter, outbox: outbox);
    addTearDown(container.dispose);

    await container
        .read(inventoryProvider.notifier)
        .add(
          const Ingredient(
            id: 'ingredient_1',
            name: 'Milk',
            quantity: '1',
            unit: 'box',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
          ),
        );

    final operation = outbox.loadPending().single;
    expect(operation.entityType, SyncEntityType.inventoryItem);
    expect(operation.entityId, 'ingredient_1');
    expect(operation.operation, SyncOperationType.create);
    expect(operation.patch, containsPair('name', 'Milk'));
  });

  test('custom recipe add enqueues create sync operation', () async {
    final adapter = InMemoryStorageAdapter();
    final outbox = SyncOutboxRepo(adapter);
    final container = _container(adapter: adapter, outbox: outbox);
    addTearDown(container.dispose);

    await container
        .read(customRecipesProvider.notifier)
        .add(
          const Recipe(
            id: 'recipe_1',
            name: 'Tomato Pasta',
            category: '晚餐',
            difficulty: 2,
            cookingMinutes: 20,
            description: '',
            ingredients: [],
            steps: [],
          ),
        );

    final operation = outbox.loadPending().single;
    expect(operation.entityType, SyncEntityType.customRecipe);
    expect(operation.entityId, 'recipe_1');
    expect(operation.operation, SyncOperationType.create);
    expect(operation.patch, containsPair('name', 'Tomato Pasta'));
  });
}

ProviderContainer _container({
  required InMemoryStorageAdapter adapter,
  required SyncOutboxRepo outbox,
  ShoppingRepo? shoppingRepo,
}) {
  return ProviderContainer(
    overrides: [
      storageAdapterProvider.overrideWithValue(adapter),
      inventoryRepoProvider.overrideWithValue(InventoryRepo(adapter)),
      shoppingRepoProvider.overrideWithValue(
        shoppingRepo ?? ShoppingRepo(adapter),
      ),
      customRecipeRepoProvider.overrideWithValue(CustomRecipeRepo(adapter)),
      syncOutboxRepoProvider.overrideWithValue(outbox),
      selectedHouseholdIdProvider.overrideWithValue('household_1'),
      syncClientIdProvider.overrideWithValue('client_1'),
    ],
  );
}
