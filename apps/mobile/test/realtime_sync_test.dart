import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
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
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/household_content_sync.dart';
import 'package:fresh_pantry/sync/remote_pantry_repository.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

void main() {
  test('visibleRemoteRows ignores soft-deleted rows', () {
    final rows = [
      {'id': 'item_1', 'name': 'Milk', 'deletedAt': null},
      {'id': 'item_2', 'name': 'Rice', 'deletedAt': '2026-05-27T00:00:00.000Z'},
      {
        'id': 'item_3',
        'name': 'Eggs',
        'deleted_at': '2026-05-27T00:00:00.000Z',
      },
    ];

    final visible = visibleRemoteRows(rows);

    expect(visible.map((row) => row['id']), ['item_1']);
  });

  testWidgets('HouseholdContentSync loads and watches shared household rows', (
    tester,
  ) async {
    final adapter = InMemoryStorageAdapter();
    final remote = FakeRemotePantryRepository(
      inventoryRows: [_inventoryRow('11111111-1111-1111-1111-111111111111')],
      shoppingRows: [_shoppingRow('22222222-2222-2222-2222-222222222222')],
      customRecipeRows: [_recipeRow('33333333-3333-3333-3333-333333333333')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageAdapterProvider.overrideWithValue(adapter),
          inventoryRepoProvider.overrideWithValue(InventoryRepo(adapter)),
          shoppingRepoProvider.overrideWithValue(ShoppingRepo(adapter)),
          customRecipeRepoProvider.overrideWithValue(CustomRecipeRepo(adapter)),
          syncOutboxRepoProvider.overrideWithValue(SyncOutboxRepo(adapter)),
          selectedHouseholdIdProvider.overrideWithValue('household_1'),
          remotePantryRepositoryProvider.overrideWithValue(remote),
          syncPushPendingProvider.overrideWithValue(() async {}),
        ],
        child: HouseholdContentSync(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Consumer(
              builder: (context, ref, _) {
                final inventory = ref.watch(inventoryProvider);
                final shopping = ref.watch(shoppingProvider);
                final recipes = ref.watch(customRecipesProvider);
                return Text(
                  '${inventory.map((item) => item.name).join(',')}|'
                  '${shopping.map((item) => item.name).join(',')}|'
                  '${recipes.map((recipe) => recipe.name).join(',')}',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Milk|Eggs|Omelette'), findsOneWidget);

    remote.inventoryController.add([
      _inventoryRow(
        '11111111-1111-1111-1111-111111111111',
        deletedAt: '2026-05-28T00:00:00.000Z',
      ),
      _inventoryRow('44444444-4444-4444-4444-444444444444', name: 'Rice'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Rice|Eggs|Omelette'), findsOneWidget);

    await remote.close();
  });

  testWidgets(
    'HouseholdContentSync uploads legacy local rows before applying empty remote',
    (tester) async {
      final adapter = InMemoryStorageAdapter();
      final inventoryRepo = InventoryRepo(adapter)
        ..saveItems([
          const Ingredient(
            id: 'legacy_inventory_1',
            name: 'Watermelon',
            quantity: '1',
            unit: '个',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
          ),
        ]);
      final shoppingRepo = ShoppingRepo(adapter)
        ..saveItems([
          const ShoppingItem(
            id: 'legacy_shopping_1',
            name: 'Yogurt',
            detail: '',
            category: '乳品蛋类',
          ),
        ]);
      final customRecipeRepo = CustomRecipeRepo(adapter)
        ..saveRecipes([
          const Recipe(
            id: 'legacy_recipe_1',
            name: 'Fruit Bowl',
            category: '早餐',
            difficulty: 1,
            cookingMinutes: 5,
            description: '',
            ingredients: [],
            steps: [],
          ),
        ]);
      final remote = FakeRemotePantryRepository(
        inventoryRows: [],
        shoppingRows: [],
        customRecipeRows: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageAdapterProvider.overrideWithValue(adapter),
            inventoryRepoProvider.overrideWithValue(inventoryRepo),
            shoppingRepoProvider.overrideWithValue(shoppingRepo),
            customRecipeRepoProvider.overrideWithValue(customRecipeRepo),
            syncOutboxRepoProvider.overrideWithValue(SyncOutboxRepo(adapter)),
            selectedHouseholdIdProvider.overrideWithValue('household_1'),
            remotePantryRepositoryProvider.overrideWithValue(remote),
            syncPushPendingProvider.overrideWithValue(() async {}),
          ],
          child: HouseholdContentSync(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Consumer(
                builder: (context, ref, _) {
                  final inventory = ref.watch(inventoryProvider);
                  final shopping = ref.watch(shoppingProvider);
                  final recipes = ref.watch(customRecipesProvider);
                  return Text(
                    '${inventory.map((item) => item.name).join(',')}|'
                    '${shopping.map((item) => item.name).join(',')}|'
                    '${recipes.map((recipe) => recipe.name).join(',')}',
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Watermelon|Yogurt|Fruit Bowl'), findsOneWidget);
      expect(remote.inventoryRows.single['name'], 'Watermelon');
      expect(remote.shoppingRows.single['name'], 'Yogurt');
      expect(remote.customRecipeRows.single['name'], 'Fruit Bowl');
      expect(remote.inventoryRows.single['id'], matches(_uuidPattern));
      expect(inventoryRepo.loadAll().single.id, matches(_uuidPattern));
      expect(shoppingRepo.loadAll().single.id, matches(_uuidPattern));
      expect(customRecipeRepo.loadAll().single.id, matches(_uuidPattern));
      expect(inventoryRepo.loadAll().single.remoteVersion, 1);
      expect(shoppingRepo.loadAll().single.remoteVersion, 1);
      expect(customRecipeRepo.loadAll().single.remoteVersion, 1);

      await remote.close();
    },
  );

  testWidgets('HouseholdContentSync keeps local pending inventory rows', (
    tester,
  ) async {
    final adapter = InMemoryStorageAdapter();
    final remote = FakeRemotePantryRepository(
      inventoryRows: [_inventoryRow('11111111-1111-1111-1111-111111111111')],
      shoppingRows: [],
      customRecipeRows: [],
    );

    late WidgetRef latestRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageAdapterProvider.overrideWithValue(adapter),
          inventoryRepoProvider.overrideWithValue(InventoryRepo(adapter)),
          shoppingRepoProvider.overrideWithValue(ShoppingRepo(adapter)),
          customRecipeRepoProvider.overrideWithValue(CustomRecipeRepo(adapter)),
          syncOutboxRepoProvider.overrideWithValue(SyncOutboxRepo(adapter)),
          selectedHouseholdIdProvider.overrideWithValue('household_1'),
          remotePantryRepositoryProvider.overrideWithValue(remote),
          syncPushPendingProvider.overrideWithValue(() async {}),
        ],
        child: HouseholdContentSync(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Consumer(
              builder: (context, ref, _) {
                latestRef = ref;
                final inventory = ref.watch(inventoryProvider);
                return Text(inventory.map((item) => item.name).join(','));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await latestRef
        .read(inventoryProvider.notifier)
        .add(
          const Ingredient(
            id: 'local_watermelon',
            name: 'Watermelon',
            quantity: '1',
            unit: '个',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
          ),
        );
    await tester.pump();

    remote.inventoryController.add([
      _inventoryRow('11111111-1111-1111-1111-111111111111'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Milk,Watermelon'), findsOneWidget);

    await remote.close();
  });

  testWidgets(
    'HouseholdContentSync ignores pending rows from another household',
    (tester) async {
      const pendingItemId = '55555555-5555-5555-5555-555555555555';
      final adapter = InMemoryStorageAdapter();
      final inventoryRepo = InventoryRepo(adapter)
        ..saveItems([
          const Ingredient(
            id: pendingItemId,
            name: 'Watermelon',
            quantity: '1',
            unit: '个',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
          ),
        ]);
      final outbox = SyncOutboxRepo(adapter);
      await outbox.enqueue(
        SyncOperation(
          id: 'op_1',
          householdId: 'household_1',
          entityType: SyncEntityType.inventoryItem,
          entityId: pendingItemId,
          operation: SyncOperationType.create,
          patch: inventoryRepo.loadAll().single.toJson(),
          clientId: 'client_1',
          createdAt: DateTime.utc(2026, 5, 29),
        ),
      );
      final remote = FakeRemotePantryRepository(
        inventoryRows: [],
        shoppingRows: [],
        customRecipeRows: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageAdapterProvider.overrideWithValue(adapter),
            inventoryRepoProvider.overrideWithValue(inventoryRepo),
            shoppingRepoProvider.overrideWithValue(ShoppingRepo(adapter)),
            customRecipeRepoProvider.overrideWithValue(
              CustomRecipeRepo(adapter),
            ),
            syncOutboxRepoProvider.overrideWithValue(outbox),
            selectedHouseholdIdProvider.overrideWithValue('household_2'),
            remotePantryRepositoryProvider.overrideWithValue(remote),
            syncPushPendingProvider.overrideWithValue(() async {
              await outbox.removeAcknowledged({'op_1'});
            }),
          ],
          child: HouseholdContentSync(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Consumer(
                builder: (context, ref, _) {
                  final inventory = ref.watch(inventoryProvider);
                  return Text(
                    inventory.isEmpty
                        ? 'empty'
                        : inventory.map((item) => item.name).join(','),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(remote.inventoryRows, isEmpty);
      expect(find.text('empty'), findsOneWidget);

      await remote.close();
    },
  );
}

Map<String, dynamic> _inventoryRow(
  String id, {
  String name = 'Milk',
  String? deletedAt,
}) {
  return {
    'id': id,
    'name': name,
    'quantity': '1',
    'unit': 'box',
    'imageUrl': '',
    'freshnessPercent': 1.0,
    'state': 'fresh',
    'storage': 'fridge',
    'remoteVersion': 1,
    'deletedAt': deletedAt,
  };
}

Map<String, dynamic> _shoppingRow(String id) {
  return {
    'id': id,
    'name': 'Eggs',
    'detail': '6 pcs',
    'category': '乳品蛋类',
    'isChecked': false,
    'remoteVersion': 1,
  };
}

Map<String, dynamic> _recipeRow(String id) {
  return {
    'id': id,
    'name': 'Omelette',
    'category': '早餐',
    'difficulty': 1,
    'cookingMinutes': 10,
    'description': '',
    'ingredients': const [],
    'steps': const ['Cook eggs'],
    'remoteVersion': 1,
  };
}

class FakeRemotePantryRepository implements RemotePantryRepository {
  FakeRemotePantryRepository({
    required this.inventoryRows,
    required this.shoppingRows,
    required this.customRecipeRows,
  });

  final List<Map<String, dynamic>> inventoryRows;
  final List<Map<String, dynamic>> shoppingRows;
  final List<Map<String, dynamic>> customRecipeRows;
  final inventoryController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final shoppingController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final customRecipeController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  Future<List<Map<String, dynamic>>> loadInventory(String householdId) async {
    return inventoryRows;
  }

  @override
  Future<List<Map<String, dynamic>>> loadShopping(String householdId) async {
    return shoppingRows;
  }

  @override
  Future<List<Map<String, dynamic>>> loadCustomRecipes(
    String householdId,
  ) async {
    return customRecipeRows;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInventory(String householdId) {
    return inventoryController.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchShopping(String householdId) {
    return shoppingController.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId) {
    return customRecipeController.stream;
  }

  Future<void> close() async {
    await inventoryController.close();
    await shoppingController.close();
    await customRecipeController.close();
  }

  @override
  Future<void> acceptInvite(String token) {
    throw UnimplementedError();
  }

  @override
  Future<void> acceptInviteById(String inviteId) {
    throw UnimplementedError();
  }

  @override
  Future<Household> createHousehold(String name) {
    throw UnimplementedError();
  }

  @override
  Future<String> createInvite({required String householdId, String? email}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dissolveHousehold(String householdId) {
    throw UnimplementedError();
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(
    String householdId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<Household>> loadHouseholds() {
    throw UnimplementedError();
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) {
    throw UnimplementedError();
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() {
    throw UnimplementedError();
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> revokeInvite(String inviteId) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateHouseholdName(String householdId, String name) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertCustomRecipes(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    _upsertRows(customRecipeRows, rows);
  }

  @override
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    _upsertRows(inventoryRows, rows);
  }

  @override
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    _upsertRows(shoppingRows, rows);
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

void _upsertRows(
  List<Map<String, dynamic>> target,
  List<Map<String, dynamic>> rows,
) {
  for (final row in rows) {
    final id = row['id'];
    final remoteVersion = switch (row['remoteVersion']) {
      final num value when value > 0 => value.toInt(),
      _ => 1,
    };
    final stored = {...row, 'remoteVersion': remoteVersion};
    final index = target.indexWhere((existing) => existing['id'] == id);
    if (index == -1) {
      target.add(Map<String, dynamic>.from(stored));
    } else {
      target[index] = {...target[index], ...stored};
    }
  }
}
