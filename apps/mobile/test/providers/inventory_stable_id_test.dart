import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/sync/sync_ids.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

Ingredient _blank(String name) => Ingredient(
      id: '',
      name: name,
      quantity: '1',
      unit: '个',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
    );

void main() {
  test('add assigns a stable uuid even when local-only (no household)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = InventoryRepo(db);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      inventoryRepoProvider.overrideWithValue(repo),
      selectedHouseholdIdProvider.overrideWithValue(''), // local-only
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await container.read(inventoryProvider.notifier).add(_blank('牛奶'));

    final saved = await repo.loadAllFor('');
    expect(saved, hasLength(1));
    expect(isUuid(saved.single.id), isTrue,
        reason: 'local-only items must be born with a stable uuid, not blank');
  });
}
