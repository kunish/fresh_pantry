import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
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
  Future<void> removeMember(String targetUserId) {
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
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) {
    throw UnimplementedError();
  }
}
