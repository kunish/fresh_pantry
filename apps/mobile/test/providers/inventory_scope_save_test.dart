import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

void main() {
  test('add writes under active household scope', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = InventoryRepo(db);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      inventoryRepoProvider.overrideWithValue(repo),
      selectedHouseholdIdProvider.overrideWithValue('h1'),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(inventoryProvider.notifier).add(
          Ingredient(
            id: '', name: '牛奶', quantity: '1', unit: '盒', imageUrl: '',
            freshnessPercent: 1, state: FreshnessState.fresh,
          ),
        );

    expect((await repo.loadAllFor('h1')).map((e) => e.name), ['牛奶']);
    expect(await repo.loadAllFor('h2'), isEmpty);
  });
}
